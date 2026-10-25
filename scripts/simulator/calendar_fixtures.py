#!/usr/bin/env python3
"""Fictional year-calendar data. Source containers are read-only; verify all old fields and images."""
import sys, json, sqlite3, datetime, plistlib
from pathlib import Path
from look_fixtures import snapshot, hashes, png

action, raw, dest = sys.argv[1:4]
container, output = Path(raw), Path(dest)
assert '/CoreSimulator/Devices/' in str(container.resolve())
db = sqlite3.connect(container/'Documents/lolita.sqlite')
db.execute('PRAGMA foreign_keys=ON')
prefs = container/'Library/Preferences/com.lolita.ios.plist'
if action == 'seed':
    assert not db.execute('SELECT id FROM items WHERE id>=95000').fetchall()
    year = datetime.datetime.now().year
    def ms(month, day): return int(datetime.datetime(year, month, day, 12, tzinfo=datetime.timezone.utc).timestamp()*1000)
    brand, category = db.execute('SELECT brandId,categoryId FROM items LIMIT 1').fetchone()
    for ident, name in [(95001,'年历回归·分期裙'),(95002,'年历回归·历史账本')]:
        db.execute("INSERT INTO items(id,name,brandId,categoryId,status,createdAt,updatedAt) VALUES(?,?,?,?,'PENDING_BALANCE',1,1)",(ident,name,brand,category))
    db.execute("INSERT INTO prices(id,itemId,type,totalPrice,createdAt,purchaseRecordStatus) VALUES(95001,95001,'MULTI_STAGE',150,1,'TRACKED')")
    db.execute("INSERT INTO prices(id,itemId,type,totalPrice,createdAt) VALUES(95002,95002,'FULL',12.34,1)")
    db.execute("INSERT INTO orderBindings VALUES(95001,95001,'TRACKED')")
    db.execute("INSERT INTO paymentStages(id,priceId,name,amount,dueDate) VALUES(95001,95001,'定金',150,?)",(ms(1,20),))
    db.execute("INSERT INTO payments(id,priceId,amount,dueDate,isPaid,paidDate,createdAt,stageId) VALUES(95001,95001,40,?,1,?,1,95001)",(ms(1,20),ms(2,20)))
    db.execute("INSERT INTO payments(id,priceId,amount,dueDate,isPaid,createdAt,stageId) VALUES(95002,95001,10,?,1,1,95001)",(ms(1,20),))
    db.execute("INSERT INTO payments(id,priceId,amount,dueDate,isPaid,paidDate,createdAt) VALUES(95003,95002,12.34,?,1,?,1)",(ms(1,20),ms(3,20)))
    db.commit()
    p=plistlib.loads(prefs.read_bytes()); shared=container/'Documents/images/ledger-original.png'; assert shared.exists()
    p['paymentCalendarBackgroundPath']=str(shared);p['showTotalPrice']=True
    prefs.write_bytes(plistlib.dumps(p))
    (output/'shared-background.json').write_text(json.dumps(str(shared)))
else:
    old=json.loads((output/'v8-original.json').read_text());current=snapshot(db,container)
    for table, record in old.items():
        assert record['columns']==current[table]['columns']
        for row in record['rows']: assert row in current[table]['rows'], (table,row)
    original_hash=json.loads((output/'original-image-hashes.json').read_text());current_hash=hashes(container/'Documents/images')
    for name,digest in original_hash.items(): assert current_hash.get(name)==digest,name
    actual=db.execute('SELECT amount,paidDate,stageId FROM payments WHERE priceId=95001 ORDER BY id').fetchall()
    assert len(actual)==3 and actual[-1][0]==25.25 and actual[-1][1] and actual[-1][2]==95001,actual
    assert db.execute('SELECT dueDate,paidDate FROM payments WHERE id=95002').fetchone()[1] is None
    assert db.execute('SELECT amount FROM paymentStages WHERE id=95001').fetchone()==(150.0,)
    p=plistlib.loads(prefs.read_bytes());assert p['paymentCalendarBackgroundPath']=='' and p['showTotalPrice'] is True
    assert db.execute('PRAGMA integrity_check').fetchone()==('ok',);assert not db.execute('PRAGMA foreign_key_check').fetchall()
    result=dict(passed=True,tables=len(old),old_rows=sum(len(r['rows']) for r in old.values()),old_images=len(original_hash),original_fields_and_images_preserved=True,partial_actual=25.25,remaining=74.75,unknown_date_preserved=True,shared_background_image_preserved=True,integrity='ok',foreign_keys='ok')
    (output/'preservation-result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2));print(json.dumps(result,ensure_ascii=False))
