#!/usr/bin/env python3
"""Fictional batch-five fixtures; compare every pre-existing row and original image byte."""
import sys,json,sqlite3,hashlib,shutil,struct,zlib,datetime
from pathlib import Path

def tables(db):
    return [r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name<>'grdb_migrations' ORDER BY name")]
def normal(value, container):
    if isinstance(value,str):
        if value.startswith(('[','{')):
            try:
                decoded=json.loads(value)
                if isinstance(decoded,(list,dict)):
                    def walk(v):
                        if isinstance(v,list):return [walk(x) for x in v]
                        if isinstance(v,dict):return {k:walk(x) for k,x in v.items()}
                        return normal(v,container)
                    return json.dumps(walk(decoded),ensure_ascii=False,sort_keys=True,separators=(',',':'))
            except (ValueError,TypeError):pass
        return value.replace(str(container/'Documents/images')+'/', '<images>/')
    return value
def snapshot(db,container):
    return {t:dict(columns=[r[1] for r in db.execute(f'PRAGMA table_info("{t}")')],rows=[[normal(v,container) for v in r] for r in db.execute(f'SELECT * FROM "{t}"')]) for t in tables(db)}
def hashes(folder):return {p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in folder.glob('*') if p.is_file()}
def png(path,color):
    def chunk(kind,data):return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
    w,h=240,320
    pixels=b''.join(b'\x00'+b''.join(bytes(color if (30<x<210 and 30<y<290 and (y>85 or 70<x<170)) else (250,245,240)) for x in range(w)) for y in range(h))
    path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(pixels))+chunk(b'IEND',b''))
def main():
    action,container,output=sys.argv[1],Path(sys.argv[2]),Path(sys.argv[3]);assert '/CoreSimulator/Devices/' in str(container.resolve());output.mkdir(parents=True,exist_ok=True)
    docs=container/'Documents';database=docs/'lolita.sqlite'
    if action=='copy-v8':
        source=Path(sys.argv[4]);assert '/CoreSimulator/Devices/' in str(source.resolve()) and source!=container
        docs.mkdir(exist_ok=True)
        with sqlite3.connect(source/'Documents/lolita.sqlite') as old:
            assert 'v8-import-sessions' in [r[0] for r in old.execute('SELECT identifier FROM grdb_migrations')]
            assert len(tables(old))==26
            (output/'v8-original.json').write_text(json.dumps(snapshot(old,source),ensure_ascii=False,indent=2))
            with sqlite3.connect(database) as new:old.backup(new)
        shutil.copytree(source/'Documents/images',docs/'images',dirs_exist_ok=True)
        (output/'original-image-hashes.json').write_text(json.dumps(hashes(docs/'images'),indent=2))
        return
    db=sqlite3.connect(database);db.execute('PRAGMA foreign_keys=ON')
    if action=='snapshot-v8':
        assert len(tables(db))==26
        (output/'v8-original.json').write_text(json.dumps(snapshot(db,container),ensure_ascii=False,indent=2))
        (output/'original-image-hashes.json').write_text(json.dumps(hashes(docs/'images'),indent=2))
    elif action=='seed':
        original=json.loads((output/'v8-original.json').read_text());current=snapshot(db,container)
        assert original==current, 'v8 launch/relocation changed original business data'
        (output/'v8-upgrade-result.json').write_text(json.dumps(dict(passed=True,tables=26,old_rows=sum(len(x['rows']) for x in original.values()),original_images=hashes(docs/'images')==json.loads((output/'original-image-hashes.json').read_text())),indent=2))
        assert db.execute('SELECT COUNT(*) FROM items WHERE id>=9000').fetchone()[0]==0,'Refuse reseeding'
        images=docs/'images';images.mkdir(exist_ok=True)
        for name,color in [('look-blue.png',(80,140,210)),('look-red.png',(205,85,115)),('look-white.png',(180,200,210))]:png(images/name,color)
        now=9000000000000
        db.execute("INSERT INTO brands(id,name,isPreset,createdAt) VALUES(9001,'回归搭配品牌',0,1)")
        cats=[(9001,'改名主裙','JSK'),(9002,'改名头饰','KC'),(9003,'改名袜装','TIGHTS'),(9004,'改名包袋','HANDBAG'),(9005,'改名上衣','BLOUSE'),(9006,'另一条主裙','OP')]
        for cid,name,semantic in cats:db.execute('INSERT INTO categories(id,name,"group",isPreset,createdAt,categorySemantic) VALUES(?,?,?,0,1,?)',(cid,name,'CLOTHING' if cid in [9001,9005,9006] else 'ACCESSORY',semantic))
        for cid,name in [(9001,'回归·原套装'),(9002,'回归·多页分享')]:db.execute('INSERT INTO coordinates(id,name,description,imageUrls,createdAt,updatedAt) VALUES(?,?,?, ?,1,?)',(cid,name,'私密套装备注',json.dumps([str(images/'look-blue.png')]),now+cid))
        def item(i,name,cat,color='蓝色',coord=None,status='OWNED',included=False,parent=None):
            db.execute('''INSERT INTO items(id,name,brandId,categoryId,status,description,colors,season,style,imageUrls,coordinateId,coordinateOrder,createdAt,updatedAt,parentItemId,includedInParentPrice,source,importOrderKeys) VALUES(?,?,9001,?,?,'私密服饰备注',?,'春,秋','古典',?,?,0,1,?,?,?,'私密购买渠道','["preserved-key"]')''',(i,name,cat,status,json.dumps([color]),json.dumps([str(images/('look-red.png' if color=='红色' else 'look-blue.png'))]),coord,now+20000-i,parent,int(included)))
        item(9001,'回归·搭配主件',9001,coord=9001);item(9002,'回归·蓝色头饰',9002);item(9003,'回归·红色头饰',9002,'红色');item(9004,'回归·蓝色袜子',9003);item(9005,'回归·红色袜子',9003,'红色');item(9006,'回归·包袋',9004);item(9007,'回归·衬衫',9005);item(9008,'回归·其他主裙',9006);item(9009,'回归·心愿头饰',9002,status='WISHED');item(9010,'回归·共价小物',9002,coord=9001,included=True,parent=9001)
        for index in range(13):item(9200+index,f'回归·分享服饰{index+1:02}',9002,coord=9002)
        # Current ledger for the original set is deliberately private, never copied into cards.
        db.execute("INSERT INTO prices(id,itemId,type,totalPrice,createdAt,purchaseRecordStatus) VALUES(9001,9001,'FULL',1234.56,1,'TRACKED')")
        db.execute("INSERT INTO orderBindings(itemId,priceId,purchaseRecordStatus) VALUES(9001,9001,'TRACKED')")
        db.execute("INSERT INTO payments(id,priceId,amount,dueDate,isPaid,paidDate,createdAt) VALUES(9001,9001,1234.56,1,1,NULL,1)")
        db.execute('INSERT INTO outfitLogs(id,date,note,imageUrls,createdAt,updatedAt) VALUES(9001,?,?,?,1,1)',(int(datetime.datetime(2026,10,22,12).timestamp()*1000),'回归·私密穿搭笔记',json.dumps([str(images/'look-blue.png'),str(images/'look-red.png')])))
        db.execute('INSERT INTO outfitItemCrossRef(outfitLogId,itemId) VALUES(9001,9001)');db.execute('INSERT INTO outfitItemCrossRef(outfitLogId,itemId) VALUES(9001,9002)')
        today=int(datetime.datetime.now().replace(hour=12,minute=0,second=0,microsecond=0).timestamp()*1000)
        db.execute('INSERT INTO outfitLogs(id,date,note,imageUrls,createdAt,updatedAt) VALUES(9002,?,?,?,11,12)',(today,'回归·今日原笔记',json.dumps([str(images/'look-blue.png')])))
        db.execute('INSERT INTO outfitItemCrossRef(outfitLogId,itemId) VALUES(9002,9001)')
        db.commit();db.execute('PRAGMA wal_checkpoint(TRUNCATE)')
        (output/'before-ui.json').write_text(json.dumps(snapshot(db,container),ensure_ascii=False,indent=2));(output/'all-image-hashes.json').write_text(json.dumps(hashes(images),indent=2))
    elif action=='verify':
        current=snapshot(db,container);original=json.loads((output/'v8-original.json').read_text())
        for t,old in original.items():
            assert old['columns']==current[t]['columns'],t
            for row in old['rows']:assert row in current[t]['rows'],(t,row)
        before=json.loads((output/'before-ui.json').read_text())
        expected=next(r[0] for r in db.execute("SELECT id FROM coordinates WHERE name='回归·完成整套'"))
        assert [r[0] for r in db.execute('SELECT id FROM items WHERE coordinateId=? ORDER BY coordinateOrder',(expected,))]==[9001,9007,9003,9006]
        # Only these fixture fields may change during the actual interaction tests.
        mutable={'items':({9001,9003,9006,9007},{'coordinateId','coordinateOrder','updatedAt'}),'outfitLogs':({9002},{'note','updatedAt'}),'outfitItemCrossRef':({9002},set())}
        for t,old in before.items():
            cols=old['columns'];rows=current[t]['rows']
            ids,allowed=mutable.get(t,(set(),set()))
            for row in old['rows']:
                if row[0] in ids and t=='outfitItemCrossRef':continue
                if row[0] in ids:
                    selected=next(r for r in rows if r[0]==row[0]);assert all(a==b for c,a,b in zip(cols,row,selected) if c not in allowed),(t,row,selected)
                else:assert row in rows,(t,row)
        assert db.execute('SELECT note FROM outfitLogs WHERE id=9002').fetchone()[0]=='回归·今日交互更新'
        assert [r[0] for r in db.execute('SELECT itemId FROM outfitItemCrossRef WHERE outfitLogId=9002 ORDER BY itemId')]==[9001,9007]
        for name,sha in json.loads((output/'all-image-hashes.json').read_text()).items():assert hashlib.sha256((docs/'images'/name).read_bytes()).hexdigest()==sha,name
        assert db.execute('SELECT count(*) FROM payments').fetchone()[0]==len(before['payments']['rows'])
        assert db.execute('SELECT count(*) FROM prices').fetchone()[0]==len(before['prices']['rows'])
        assert db.execute('PRAGMA foreign_key_check').fetchall()==[];assert db.execute('PRAGMA integrity_check').fetchone()[0]=='ok'
        shares=list((container/'Library/Caches/share-cards').glob('*/*.png'));assert shares
        for share in shares:
            data=share.read_bytes();assert data[:8]==b'\x89PNG\r\n\x1a\n';w,h=struct.unpack('>II',data[16:24]);assert w==1080 and 100<h<4000,(share,w,h)
        result=dict(passed=True,all_26_original_tables_preserved=True,original_rows=sum(len(x['rows']) for x in original.values()),old_images_sha256_preserved=True,new_set_members=[9001,9007,9003,9006],old_set_and_history_kept=True,today_same_record_no_duplicate=True,original_cash_unchanged=True,share_pngs=len(shares),foreign_keys='ok',integrity='ok')
        (output/'business-result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2));print(json.dumps(result,ensure_ascii=False))
    db.close()
if __name__=='__main__':main()
