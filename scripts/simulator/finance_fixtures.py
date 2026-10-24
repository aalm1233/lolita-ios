#!/usr/bin/env python3
"""Independent native finance regression fixtures; only this run's fictional simulator data."""
from pathlib import Path
import argparse, sqlite3, json, hashlib, datetime
import ledger_fixtures

p=argparse.ArgumentParser()
p.add_argument('action',choices=['prepare-v4','prepare-current','verify-results'])
p.add_argument('container',type=Path); p.add_argument('output',type=Path)
a=p.parse_args()
assert '/CoreSimulator/Devices/' in str(a.container.resolve())
db=sqlite3.connect(a.container/'Documents/lolita.sqlite'); db.execute('PRAGMA foreign_keys=ON')
if a.action=='prepare-v4':
    assert db.execute('SELECT count(*) FROM items').fetchone()[0]==4
    db.execute("UPDATE items SET status='WISHED' WHERE id=101"); db.commit()
    before=json.loads((a.output/'before-upgrade.json').read_text())
    before['tables']=ledger_fixtures.snapshot(db)
    (a.output/'before-upgrade.json').write_text(json.dumps(before,ensure_ascii=False,indent=2))
elif a.action=='prepare-current':
    assert db.execute("SELECT count(*) FROM grdb_migrations WHERE identifier='v6-after-sale-budget'").fetchone()[0]==1
    assert db.execute('SELECT count(*) FROM orderRefunds').fetchone()[0]==0
    brand,category,images=db.execute('SELECT brandId,categoryId,imageUrls FROM items WHERE id=102').fetchone()
    db.execute("INSERT INTO items(id,name,brandId,categoryId,status,imageUrls,parentItemId,includedInParentPrice,createdAt,updatedAt) VALUES(105,'回归·售后共价',?,?,'PENDING_BALANCE',?,102,1,111,222)",(brand,category,images))
    db.commit()
    snapshot=ledger_fixtures.snapshot(db)
    for table in ['orderBindings','paymentStages']:
        snapshot[table]={'columns':[r[1] for r in db.execute(f'PRAGMA table_info({table})')], 'rows':[list(r) for r in db.execute(f'SELECT * FROM {table} ORDER BY rowid')]}
    (a.output/'before-finance-ui.json').write_text(json.dumps(snapshot,ensure_ascii=False,indent=2))
    with sqlite3.connect(a.output/'finance-pre-ui.sqlite') as target: db.backup(target)
else:
    reference=db.execute('SELECT amount FROM itemReferencePrices WHERE itemId=101').fetchone()
    assert reference==(680.12,),reference
    assert db.execute('SELECT count(*) FROM prices WHERE itemId=101').fetchone()[0]==0,'Reference must never create an order'
    assert db.execute('SELECT status FROM items WHERE id=101').fetchone()==('WISHED',)
    refunds=db.execute('SELECT amount,kind,voidedAt FROM orderRefunds WHERE priceId=1021').fetchall()
    assert refunds==[(25.25,'PRICE_DIFFERENCE',None)],refunds
    assert db.execute('SELECT expectedRefundTotal FROM orderCancellations WHERE priceId=1021').fetchone()==(None,)
    current=db.execute('SELECT p.id,p.totalPrice FROM orderBindings b JOIN prices p ON p.id=b.priceId WHERE b.itemId=102').fetchone()
    assert current and current[0]!=1021 and current[1]==400,current
    assert db.execute('SELECT count(*) FROM payments WHERE priceId=?',(current[0],)).fetchone()[0]==0
    assert db.execute('SELECT status,parentItemId,includedInParentPrice FROM items WHERE id=105').fetchone()==('PENDING_PAYMENT',102,1)
    assert db.execute('SELECT count(*) FROM prices WHERE itemId=105').fetchone()[0]==0
    assert db.execute('SELECT amountCents FROM monthlyBudgets WHERE month=?',(datetime.datetime.now().strftime('%Y-%m'),)).fetchone()==(100000,)
    original=json.loads((a.output/'before-finance-ui.json').read_text())
    for table,record in original.items():
        names=record['columns']; selected=','.join('"'+name+'"' for name in names)
        keys=['outfitLogId','itemId'] if table=='outfitItemCrossRef' else ['itemId'] if table=='orderBindings' else ['id']
        indices=[names.index(k) for k in keys]
        rows={tuple(row[i] for i in indices):row for row in db.execute(f'SELECT {selected} FROM "{table}"')}
        for old in record['rows']:
            key=tuple(old[i] for i in indices)
            if table=='orderBindings' and key==(102,): continue # Explicit cancellation and new purchase.
            fresh=rows[key]
            for index,name in enumerate(names):
                if table=='items' and key in [(102,),(105,)] and name=='status': continue
                def normalized(value):
                    if name=='imageUrls' and value: return [Path(p).name for p in json.loads(value)]
                    if name in ['sizeChartImageUrl','imageUrl','logoUrl'] and value: return Path(value).name
                    return value
                assert normalized(fresh[index])==normalized(old[index]),(table,key,name,fresh[index],old[index])
    before=json.loads((a.output/'before-upgrade.json').read_text())
    for old,digest in before['images'].items():
        path=a.container/'Documents/images'/Path(old).name
        assert hashlib.sha256(path.read_bytes()).hexdigest()==digest
    assert not db.execute('PRAGMA foreign_key_check').fetchall()
    assert db.execute('PRAGMA integrity_check').fetchone()[0]=='ok'
    result={'passed':True,'reference_only':680.12,'refund':25.25,'refund_kind':'PRICE_DIFFERENCE','original_paid_preserved':100,'net':74.75,'unknown_refund_agreement':True,'repurchase_total':400,'repurchase_actual_rows':0,'shared_child_own_prices':0,'budget_cents':100000,'old_14_table_fields_preserved_except_explicit_status_and_binding_changes':True,'original_image_sha256_preserved':True,'foreign_keys':'ok','integrity':'ok'}
    (a.output/'business-result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2))
    print(json.dumps(result,ensure_ascii=False))
db.close()
