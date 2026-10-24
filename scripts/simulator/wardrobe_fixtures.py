#!/usr/bin/env python3
"""Fictional data and independent assertions for real native registration/storage tests."""
from pathlib import Path
import argparse,sqlite3,json,hashlib,struct,zlib
import ledger_fixtures
p=argparse.ArgumentParser();p.add_argument('action',choices=['prepare-current','verify-results']);p.add_argument('container',type=Path);p.add_argument('output',type=Path);a=p.parse_args()
assert '/CoreSimulator/Devices/' in str(a.container.resolve())
db=sqlite3.connect(a.container/'Documents/lolita.sqlite');db.execute('PRAGMA foreign_keys=ON')
if a.action=='prepare-current':
    assert db.execute("SELECT count(*) FROM grdb_migrations WHERE identifier='v7-wardrobe-storage'").fetchone()[0]==1
    db.execute("INSERT INTO locations(id,name,description,sortOrder,createdAt,updatedAt) VALUES(102,'回归衣帽间','第二房间',2,111,222)")
    db.commit()
    snapshot=ledger_fixtures.snapshot(db)
    for table in ['orderBindings','paymentStages','itemReferencePrices','orderRefunds','orderCancellations','monthlyBudgets']:
        snapshot[table]={'columns':[r[1] for r in db.execute(f'PRAGMA table_info({table})')],'rows':[list(r) for r in db.execute(f'SELECT * FROM {table} ORDER BY rowid')]}
    (a.output/'before-wardrobe-ui.json').write_text(json.dumps(snapshot,ensure_ascii=False,indent=2))
    with sqlite3.connect(a.output/'wardrobe-pre-ui.sqlite') as target:db.backup(target)
    def chunk(kind,data):return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
    for suffix,color in [('a',(80,160,230)),('b',(235,160,80))]:
        pixels=b''.join(b'\0'+bytes(color)*120 for _ in range(160))
        png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',120,160,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(pixels))+chunk(b'IEND',b'')
        (a.output/f'picker-{suffix}.png').write_bytes(png)
else:
    original=json.loads((a.output/'before-wardrobe-ui.json').read_text())
    for table,record in original.items():
        names=record['columns']; selected=','.join('"'+name+'"' for name in names)
        keys=['outfitLogId','itemId'] if table=='outfitItemCrossRef' else ['itemId'] if table in ['orderBindings','itemReferencePrices'] else ['priceId'] if table=='orderCancellations' else ['month'] if table=='monthlyBudgets' else ['id']
        indices=[names.index(k) for k in keys]
        rows={tuple(row[i] for i in indices):row for row in db.execute(f'SELECT {selected} FROM "{table}"')}
        for old in record['rows']:
            key=tuple(old[i] for i in indices);fresh=rows[key]
            for index,name in enumerate(names):
                if table=='items' and key==(101,) and name in ['name','categoryId','size','imageUrls','sizeChartImageUrl','updatedAt','locationId','composition','specificationsJson','sizeChartImageUrls']:continue
                if table=='items' and key==(103,) and name in ['locationId','storageNodeId']:continue
                if table=='categories' and name=='name' and old[index]=='鞋子':continue
                def normalized(value):
                    if name in ['imageUrls','sizeChartImageUrls'] and value:return [Path(p).name for p in json.loads(value)]
                    if name in ['sizeChartImageUrl','imageUrl','logoUrl'] and value:return Path(value).name
                    return value
                assert normalized(fresh[index])==normalized(old[index]),(table,key,name,fresh[index],old[index])
    db.row_factory=sqlite3.Row
    item=db.execute('SELECT * FROM items WHERE id=101').fetchone()
    assert item['name']=='回归·登记完成' and item['size']=='定制 24.5' and item['composition']=='PAIR',dict(item)
    assert json.loads(item['specificationsJson'])['footwear']['heelHeightCm']=='5.5'
    assert db.execute('SELECT name,categorySemantic FROM categories WHERE id=?',(item['categoryId'],)).fetchone()[:]==('回归鞋履','OTHER_FOOTWEAR')
    photos=json.loads(item['imageUrls']); details=json.loads(item['sizeChartImageUrls'])
    assert len(photos)==3 and len(details)==2 and len(set(photos))==3 and len(set(details))==2
    assert Path(photos[0]).name!='ledger-original.png','Explicitly selected cover must become first'
    assert any(Path(path).name=='ledger-original.png' for path in photos),'Original shared image must remain'
    assert item['sizeChartImageUrl']==details[0]
    assert item['locationId'] is None and item['storageNodeId'] is None,'Explicit temporary-node deletion clears placement only'
    placed=db.execute('SELECT name,locationId,storageNodeId,createdAt,updatedAt FROM items WHERE id=103').fetchone()
    assert placed[:]==('回归·历史已购',102,2,111,222),placed[:]
    nodes=[tuple(r) for r in db.execute('SELECT id,name,locationId,parentNodeId FROM storageNodes ORDER BY id')]
    assert nodes==[(1,'回归柜架',102,None),(2,'回归层格',102,1)],nodes
    assert db.execute('SELECT count(*) FROM itemDrafts').fetchone()[0]==0
    assert db.execute("SELECT count(*) FROM items WHERE name='回归·大字登记' AND status='OWNED'").fetchone()[0]==1
    before=json.loads((a.output/'before-upgrade.json').read_text())
    for old,digest in before['images'].items():
        path=a.container/'Documents/images'/Path(old).name
        assert hashlib.sha256(path.read_bytes()).hexdigest()==digest
    for path in photos+details:
        current=a.container/'Documents/images'/Path(path).name
        assert current.is_file() and current.stat().st_size>0
    assert not db.execute('PRAGMA foreign_key_check').fetchall()
    assert db.execute('PRAGMA integrity_check').fetchone()[0]=='ok'
    result={'passed':True,'old_18_tables_preserved_except_explicit_registration_category_and_placement_changes':True,'old_image_sha256_preserved':True,'new_photo_count':3,'detail_image_count':2,'explicit_cover':True,'stable_category':'OTHER_FOOTWEAR','custom_size':'定制 24.5','composition':'PAIR','heel_height':'5.5','moved_subtree_nodes':2,'placed_item':103,'new_room':102,'preserved_item_timestamps':[111,222],'discarded_edits_not_committed':True,'drafts_cleared_after_save_or_discard':True,'unowned_item_placement_unchanged':True,'storage_deletion_keeps_item_and_images':True,'new_dark_accessibility_registration':True,'foreign_keys':'ok','integrity':'ok'}
    (a.output/'business-result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2))
    print(json.dumps(result,ensure_ascii=False))
db.close()
