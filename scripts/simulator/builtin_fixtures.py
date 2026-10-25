#!/usr/bin/env python3
"""Check every old row/image; allow only the documented one-time blank artwork fill."""
import json,sqlite3,sys,hashlib
from pathlib import Path
from look_fixtures import snapshot,hashes
mode,container,output=sys.argv[1],Path(sys.argv[2]),Path(sys.argv[3])
assert mode in ('fresh','upgrade','experience')
assert '/CoreSimulator/Devices/' in str(container.resolve())
root=Path(__file__).resolve().parents[2]
catalog=json.loads((root/'Sources/Resources/builtin/catalog.json').read_text())
assets={n.strip().lower():x['assetPath'] for x in catalog['brands'] for n in x['names']}
rooms={x['name']:x['assetPath'] for x in catalog['rooms']}
with sqlite3.connect(container/'Documents/lolita.sqlite') as db:
    current=snapshot(db,container);filled=[];old_rows=0;old_images={};original_storage_nodes=0
    if mode in ('upgrade','experience'):
        original=json.loads((output/'v8-original.json').read_text());old_images=json.loads((output/'original-image-hashes.json').read_text())
        original_storage_nodes=len(original['storageNodes']['rows'])
        for t,old in original.items():
            new=current[t];assert old['columns']==new['columns'],t
            if t not in ('brands','categories','locations','styles','seasons','sources','storageNodes'):
                assert new['rows']==old['rows'],('Unexpected business rows',t)
            cols=old['columns'];old_rows+=len(old['rows'])
            for row in old['rows']:
                if row in new['rows']:continue
                assert t in ('brands','locations'),(t,row)
                name=row[cols.index('name')];col='logoUrl' if t=='brands' else 'imageUrl'
                asset=assets.get(name.strip().lower()) if t=='brands' else rooms.get(name)
                assert asset and not (row[cols.index(col)] or '').strip(),(t,row)
                actual=next(r for r in new['rows'] if r[cols.index('id')]==row[cols.index('id')])
                assert all(a==b for c,a,b in zip(cols,row,actual) if c!=col),(t,row,actual)
                file=container/'Documents/images'/actual[cols.index(col)].removeprefix('<images>/')
                assert file.read_bytes()==(root/'Sources/Resources'/asset).read_bytes(),file
                filled.append(dict(table=t,id=row[cols.index('id')],field=col))
        for name,h in old_images.items():assert hashlib.sha256((container/'Documents/images'/name).read_bytes()).hexdigest()==h,name
    assert db.execute('PRAGMA integrity_check').fetchone()[0]=='ok'
    assert db.execute('PRAGMA foreign_key_check').fetchall()==[]
    if mode=='fresh':
        for table,count in [('brands',201),('categories',60),('locations',5),('items',0),('prices',0),('payments',0)]:
            assert db.execute('SELECT count(*) FROM '+table).fetchone()[0]==count,table
    if mode!='experience':
        assert db.execute("SELECT count(*) FROM locations WHERE name='储物间'").fetchone()[0]==0
        assert db.execute("SELECT logoUrl FROM brands WHERE name='花与珍珠匣'").fetchone()[0] is None
        assert db.execute('SELECT count(*) FROM storageNodes WHERE name=?',('回归·已编辑的假发架',)).fetchone()[0]==1
        nodes=db.execute("SELECT imageUrl FROM storageNodes WHERE name IN ('回归·已编辑的假发架','鞋柜','袜子抽屉','配饰收纳盒')").fetchall()
        assert len(nodes)==4 and all(Path(x[0]).is_file() for x in nodes)
        assert db.execute('SELECT count(*) FROM storageNodes').fetchone()[0]==original_storage_nodes+4,'Editing duplicated a storage node'
        template_catalog=json.loads((root/'Sources/Resources/builtin/storage/catalog.json').read_text())
        assert {hashlib.sha256(Path(x[0]).read_bytes()).hexdigest() for x in nodes}=={x['sha256'] for x in template_catalog['templates']},'Editing lost a template image'
    else:
        assert db.execute('SELECT count(*) FROM storageNodes').fetchone()[0]==original_storage_nodes,'Reading templates created storage nodes'
    result=dict(passed=True,mode=mode,tables=len(current),original_rows=old_rows,original_images=len(old_images),original_business_fields_preserved=True,original_image_bytes_preserved=True,blank_artwork_fills=filled,template_nodes=4 if mode!='experience' else 0,user_deletions_kept=True if mode!='experience' else None,integrity='ok',foreign_keys='ok')
    (output/'preservation-result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');print(json.dumps(result,ensure_ascii=False))
