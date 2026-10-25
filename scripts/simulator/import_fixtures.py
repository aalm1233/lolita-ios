#!/usr/bin/env python3
"""Fictional import fixtures and independent data/image assertions; simulator only."""
import sys,json,sqlite3,hashlib,unicodedata,zipfile,struct,zlib,html
from pathlib import Path
import ledger_fixtures

def compact(v):return json.dumps(v,ensure_ascii=False,separators=(',',':'),sort_keys=True)
def digest(v):return hashlib.sha256(v.encode()).hexdigest()
def norm(v):return ' '.join(unicodedata.normalize('NFKC',v).lower().split())
def source(order):
    lines=sorted('|'.join([group(i),norm(i['name']),str(i['quantity']),f"{float(i['rawPrice']):.2f}"]) for i in order['items'])
    return digest('\x1f'.join([order['orderId'],order['orderStatus'],order['orderTime'],norm(order['shopName']),order['rawPaid'],order['rawShipping']]+lines))
def group(i):return digest('\x1f'.join([i['orderId'],'https://item.taobao.com/item.htm?id=123',norm(i['styleSpec'])]))
def order(id,paid='202.00',quantity=2):
    item=dict(orderId=id,lineIndex=0,orderTime='2026-10-01 12:00',shopName='回归导入品牌',name='回归·导入草稿',productURL='https://item.taobao.com/item.htm?id=123&spm=private',styleSpec='蓝色;M;JSK',quantity=quantity,price=100,parsedType='JSK',parsedSize='M',parsedColor='蓝色',unitOrdinal=0,rawPrice='100')
    return dict(orderId=id,orderTime=item['orderTime'],orderStatus='交易成功',shopName=item['shopName'],totalPaid=float(paid),shipping=2,items=[item],rawPaid=paid,rawShipping='2.00')
def drafts(o,b,c):
    result=[]
    for unit in range(o['items'][0]['quantity']):
        i=dict(o['items'][0]);i['sourceKey']='taobao:v1:'+group(i)+':'+str(unit);i['unitOrdinal']=unit
        result.append(dict(original=i,name=i['name'] if unit==0 else '回归·剩余商品',brandId=b,categoryId=c,color='蓝色',size='M',priceText='100.00',purchaseDate='',role='全款',manualBalanceText='',balanceDueDate=0,included=unit==0,shippingText='1.00',paidText='101.00',financialConfirmed=False,sourceSnapshotHash=source(o),identityConfirmed=False,allowDeletedReimport=False))
    return result

def main():
    action,container,output=sys.argv[1],Path(sys.argv[2]),Path(sys.argv[3]);assert '/CoreSimulator/Devices/' in str(container.resolve())
    output.mkdir(parents=True,exist_ok=True);db=sqlite3.connect(container/'Documents/lolita.sqlite');db.execute('PRAGMA foreign_keys=ON')
    if action=='seed':
        assert db.execute('SELECT COUNT(*) FROM orderImportSessions').fetchone()[0]==0
        b=db.execute('INSERT INTO brands(name,isPreset,createdAt) VALUES(?,0,1)',('回归导入品牌',)).lastrowid
        c=db.execute("SELECT id FROM categories WHERE name='JSK'").fetchone()[0]
        o=order('native-main');rows=drafts(o,b,c)
        def session(id,orders,rows,step='确认商品',files=[]):
            snapshot=dict(orders=orders,selectedKeys=[orders[0]['orderId']+':0'] if orders else [],choices={},step=step,missingAttributes=[])
            db.execute('INSERT INTO orderImportSessions(id,revision,kind,dataJson,pendingOperationId,createdAt,updatedAt) VALUES(?,1,?,?,NULL,1,?)',(id,'orders',compact(snapshot),100-len(id)))
            for n,row in enumerate(rows):db.execute('INSERT INTO orderImportRows(id,sessionId,position,sourceKey,dataJson,imagePaths,detailImagePaths) VALUES(?,?,?,?,?,?,?)',(id+':'+str(n),id,n,row['original']['sourceKey'],compact(row),'[]','[]'))
            for n,fileorder in enumerate(files):db.execute('INSERT INTO orderImportFiles(id,sessionId,name,sha256,dataJson,problem) VALUES(?,?,?,?,?,NULL)',(id+':file'+str(n),id,'来源'+str(n+1)+'.xlsx',digest(compact(fileorder)),compact([fileorder])))
        session('ui-main',[o],rows,files=[o])
        duplicate=drafts(o,b,c);duplicate[0]['financialConfirmed']=True;session('ui-duplicate',[o],duplicate,files=[o])
        a=order('native-conflict','100.00',1);z=order('native-conflict','90.00',1)
        session('ui-conflict',[],[],step='选择商品',files=[a,z])
        # Read failure is retained next to useful files; removing it must preserve other rows.
        db.execute('INSERT INTO orderImportFiles(id,sessionId,name,sha256,dataJson,problem) VALUES(?,?,?,?,?,?)',('ui-badfile','ui-conflict','损坏文件.xlsx','unread:fixture','[]','文件损坏，未读取商品'))
        # Existing editor input remains independently recoverable when supplemented.
        db.row_factory=sqlite3.Row;i=dict(db.execute('SELECT * FROM items WHERE id=103').fetchone());i['imageUrls']=[];i['sizeChartImageUrl']=None;i['sizeChartImageUrls']=[];i['colors']=json.loads(i['colors']);i['importOrderKeys']=json.loads(i['importOrderKeys']);i['includedInParentPrice']=bool(i['includedInParentPrice']);i['name']='回归·未保存编辑';i['size']='草稿专用尺码'
        photos=db.execute('SELECT imageUrls FROM items WHERE id=103').fetchone()[0]
        db.execute('INSERT INTO itemDrafts(id,targetItemId,dataJson,imagePaths,detailImagePaths,baselineUpdatedAt,updatedAt) VALUES(?,?,?,?,?,222,333)',('item.103',103,compact(i),photos,'[]'))
        db.commit();db.row_factory=None
        before={}
        tables=[r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name!='grdb_migrations'") if r[0] not in ['orderImportSessions','orderImportFiles','orderImportRows','orderImportCommits','orderImportReceipts','itemSourceRecords']]
        for table in tables:before[table]={'columns':[r[1] for r in db.execute('PRAGMA table_info('+table+')')],'rows':[list(r) for r in db.execute('SELECT * FROM '+table+' ORDER BY rowid')]}
        (output/'before-import-ui.json').write_text(json.dumps(before,ensure_ascii=False,indent=2))
        # Actual photo picker media.
        def chunk(kind,data):return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
        pixels=b''.join(b'\0'+bytes((80,160,230))*120 for _ in range(160))
        (output/'picker.png').write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',120,160,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(pixels))+chunk(b'IEND',b''))
        rows=[['订单号','订单提交时间','订单状态','店铺名称','商品名称','商品链接','型号款式','商品数量','商品金额','实付金额','运费'],['native-file','2026-10-01 12:00','交易成功','回归导入品牌','回归·文件选取','https://item.taobao.com/item.htm?id=789','蓝色;M;JSK','1','30','30','0']]
        content=''.join('<row r="%d">'%(r+1)+''.join('<c r="%s%d" t="inlineStr"><is><t>%s</t></is></c>'%(chr(65+c),r+1,html.escape(v)) for c,v in enumerate(row))+'</row>' for r,row in enumerate(rows))
        with zipfile.ZipFile(output/'导入回归.xlsx','w',zipfile.ZIP_DEFLATED) as z:
            z.writestr('[Content_Types].xml','<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>')
            z.writestr('_rels/.rels','<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>')
            z.writestr('xl/workbook.xml','<workbook xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="订单" sheetId="1" r:id="rId1"/></sheets></workbook>')
            z.writestr('xl/_rels/workbook.xml.rels','<Relationships><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>')
            z.writestr('xl/worksheets/sheet1.xml','<worksheet><sheetData>'+content+'</sheetData></worksheet>')
        print('Seeded persisted order sessions with conflicts, raw input and existing editor draft')
    elif action=='verify':
        before=json.loads((output/'before-import-ui.json').read_text())
        for table,record in before.items():
            names=record['columns'];cols=','.join('"'+n+'"' for n in names)
            keys=['outfitLogId','itemId'] if table=='outfitItemCrossRef' else ['itemId'] if table in ['orderBindings','itemReferencePrices'] else ['priceId'] if table=='orderCancellations' else ['month'] if table=='monthlyBudgets' else ['id']
            indices=[names.index(k) for k in keys];actual={tuple(r[i] for i in indices):r for r in db.execute(f'SELECT {cols} FROM "{table}"')}
            for old in record['rows']:
                key=tuple(old[i] for i in indices);new=actual[key]
                for n,col in enumerate(names):
                    if table=='items' and key==(101,) and col in ['name','imageUrls','updatedAt']:continue
                    if table=='itemDrafts' and key==('item.103',) and col in ['dataJson','updatedAt']:continue
                    def normal(v):
                        if col in ['imageUrls','imagePaths','detailImagePaths','sizeChartImageUrls'] and v:return [Path(p).name for p in json.loads(v)]
                        if col in ['sizeChartImageUrl','imageUrl','logoUrl'] and v:return Path(v).name
                        return v
                    assert normal(old[n])==normal(new[n]),(table,key,col,old[n],new[n])
        oldimages=json.loads((output/'before-upgrade.json').read_text())['images']
        for path,value in oldimages.items():assert hashlib.sha256((container/'Documents/images'/Path(path).name).read_bytes()).hexdigest()==value
        imported=db.execute("SELECT id FROM items WHERE name='回归·会话恢复'").fetchall();assert len(imported)==1,imported
        iid=imported[0][0];cash=db.execute('SELECT amount,paidDate FROM payments WHERE priceId IN (SELECT id FROM prices WHERE itemId=?)',(iid,)).fetchall();assert cash==[(101.0,None)],cash
        assert db.execute('SELECT locationId FROM items WHERE id=?',(iid,)).fetchone()[0]==101
        assert db.execute('SELECT COUNT(*) FROM orderImportReceipts WHERE itemId=?',(iid,)).fetchone()[0]==1
        product=db.execute("SELECT id,status FROM items WHERE name LIKE '回归·链接心愿%'").fetchall();assert len(product)==2 and all(r[1]=='WISHED' for r in product),product
        for id,status in product:assert db.execute('SELECT COUNT(*) FROM prices WHERE itemId=?',(id,)).fetchone()[0]==0
        product_ids=','.join(str(row[0]) for row in product)
        assert db.execute('SELECT COUNT(*) FROM itemReferencePrices WHERE amount=0 AND itemId IN ('+product_ids+')').fetchone()[0]==2
        sku=db.execute("SELECT i.colors,i.size,r.amount FROM items i JOIN itemReferencePrices r ON r.itemId=i.id WHERE i.name LIKE '回归·规格拆分%' ORDER BY i.id").fetchall()
        assert sku==[('[\"蓝色\"]','M',0.0),('[\"红色\"]','L',120.5)],sku
        assert db.execute('SELECT name FROM items WHERE id=101').fetchone()[0]=='回归·补资料完成'
        assert db.execute('SELECT name FROM items WHERE id=103').fetchone()[0]=='回归·历史已购'
        draft=json.loads(db.execute("SELECT dataJson FROM itemDrafts WHERE id='item.103'").fetchone()[0]);assert draft['name']=='回归·合入编辑' and draft['size']=='草稿专用尺码',draft
        assert not db.execute('PRAGMA foreign_key_check').fetchall();assert db.execute('PRAGMA integrity_check').fetchone()[0]=='ok'
        referenced=[]
        for table,columns in [('items',['imageUrls','sizeChartImageUrls']),('itemDrafts',['imagePaths','detailImagePaths']),('orderImportRows',['imagePaths','detailImagePaths']),('itemSourceRecords',['imagePaths'])]:
            for column in columns:
                for value, in db.execute(f'SELECT {column} FROM {table}'):
                    referenced+=json.loads(value) if value else []
        for table,column in [('items','sizeChartImageUrl'),('storageNodes','imageUrl'),('locations','imageUrl'),('brands','logoUrl')]:
            referenced += [r[0] for r in db.execute(f'SELECT {column} FROM {table}') if r[0]]
        hashes={}
        for raw in referenced:
            if raw.startswith(('https://','http://')):continue
            current=container/'Documents/images'/Path(raw).name
            assert current.is_file(),raw
            hashes[current.name]=hashlib.sha256(current.read_bytes()).hexdigest()
        (output/'all-referenced-images.json').write_text(json.dumps(hashes,indent=2))
        with sqlite3.connect(output/'after-import-ui.sqlite') as target:db.backup(target)
        result=dict(passed=True,old_20_tables_preserved_except_explicit_supplement_and_editor_fields=True,old_image_sha256_preserved=True,atomic_import_receipt=True,quantity_share_paid=101.0,post_import_room=db.execute('SELECT locationId FROM items WHERE id=?',(iid,)).fetchone()[0],unknown_paid_date_preserved=True,duplicate_import_did_not_create_item=True,product_wishes=2,zero_reference_without_order=True,explicit_sku_items=2,per_variant_references=[0,120.5],variant_colors_and_sizes_preserved=True,all_referenced_local_images_exist=True,original_item_preserved_when_merging_editor=True,foreign_keys='ok',integrity='ok')
        (output/'business-result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2));print(json.dumps(result,ensure_ascii=False))
    db.close()
if __name__=='__main__':main()
