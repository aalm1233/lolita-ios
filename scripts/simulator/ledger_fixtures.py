#!/usr/bin/env python3
"""Fictional fixtures and independent SQLite assertions for native ledger UI tests."""
import argparse
import struct
import zlib
import hashlib
import json
import sqlite3
from pathlib import Path

TABLES = ["brands", "categories", "styles", "seasons", "sources", "locations", "coordinates", "items", "prices", "payments", "outfitLogs", "outfitItemCrossRef"]

def is_builtin_blank_fill(table, columns, wanted, actual, container):
    """Only permit a previously blank image to receive the exact bundled default."""
    if table not in ('brands', 'locations'): return False
    column = 'logoUrl' if table == 'brands' else 'imageUrl'
    index = columns.index(column)
    if (wanted[index] or '').strip() or not actual[index]: return False
    root = Path(__file__).resolve().parents[2] / 'Sources/Resources'
    catalog = json.loads((root / 'builtin/catalog.json').read_text())
    name = wanted[columns.index('name')]
    if table == 'brands':
        assets = {n.strip().lower(): b['assetPath'] for b in catalog['brands'] for n in b['names']}
        asset = assets.get(name.strip().lower())
    else:
        asset = next((r['assetPath'] for r in catalog['rooms'] if r['name'] == name), None)
    if not asset: return False
    image = container / 'Documents/images' / Path(actual[index]).name
    return image.is_file() and image.read_bytes() == (root / asset).read_bytes()


def snapshot(db):
    result = {}
    for table in TABLES:
        columns = [r[1] for r in db.execute(f'PRAGMA table_info("{table}")')]
        rows = [list(r) for r in db.execute(f'SELECT * FROM "{table}" ORDER BY rowid')]
        result[table] = {"columns": columns, "rows": rows}
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["seed-v4", "verify-upgrade", "verify-results"])
    parser.add_argument("container", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    assert "/CoreSimulator/Devices/" in str(args.container.resolve()), "Only simulator containers are accepted"
    path = args.container / "Documents/lolita.sqlite"
    assert path.exists(), "Launch the app first"
    db = sqlite3.connect(path)
    db.execute("PRAGMA foreign_keys=ON")
    args.output.mkdir(parents=True, exist_ok=True)
    if args.action == "seed-v4":
        migrations = [r[0] for r in db.execute("SELECT identifier FROM grdb_migrations")]
        assert migrations == ["v1", "v2", "v3-payment-status", "v4-import-order-keys"]
        assert db.execute("SELECT count(*) FROM items").fetchone()[0] == 0, "Refuse to replace existing data"
        brand = db.execute("SELECT id FROM brands ORDER BY id LIMIT 1").fetchone()[0]
        category = db.execute("SELECT id FROM categories ORDER BY id LIMIT 1").fetchone()[0]
        images = args.container / "Documents/images"
        images.mkdir(exist_ok=True)
        photo = images / "ledger-original.png"
        def chunk(kind, data):
            return struct.pack(">I",len(data))+kind+data+struct.pack(">I",zlib.crc32(kind+data)&0xffffffff)
        pixels = b"".join(b"\x00"+b"".join(bytes((220 if (x//8+y//8)%2 else 250,180,210)) for x in range(64)) for y in range(80))
        photo.write_bytes(b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",64,80,8,2,0,0,0))+chunk(b"IDAT",zlib.compress(pixels))+chunk(b"IEND",b""))
        db.execute("INSERT INTO locations(id,name,description,sortOrder,createdAt,updatedAt) VALUES(101,'回归衣柜','原位置保留',1,111,222)")
        # Keep fixed IDs 102… available to later UI fixtures when defaults are appended.
        db.execute("UPDATE sqlite_sequence SET seq = 1000 WHERE name = 'locations'")
        db.execute("INSERT INTO coordinates(id,name,description,imageUrls,createdAt,updatedAt) VALUES(101,'回归套装','原搭配关系保留','[]',111,222)")
        for id, name, status in [(101,"回归·新购买","OWNED"),(102,"回归·主件","PENDING_BALANCE"),(103,"回归·历史已购","OWNED"),(104,"回归·多价格核对","OWNED")]:
            db.execute("""INSERT INTO items(id,name,brandId,categoryId,status,description,imageUrls,colors,season,style,size,locationId,coordinateId,importOrderKeys,createdAt,updatedAt)
                VALUES(?,?,?,?,?,'原描述保留',?,'["白色"]','春,秋','古典','M',101,101,?,111,222)""", (id,name,brand,category,status,json.dumps([str(photo)]),json.dumps([f"original-{id}"])))
        for id, item, kind, total, deposit, balance in [(1021,102,"DEPOSIT_BALANCE",300,100,200),(1031,103,"FULL",400,None,None),(1041,104,"FULL",300,None,None),(1042,104,"FULL",350,None,None)]:
            db.execute("INSERT INTO prices(id,itemId,type,totalPrice,deposit,balance,createdAt) VALUES(?,?,?,?,?,?,333)",(id,item,kind,total,deposit,balance))
        for id, price, amount, due, paid, date in [(10211,1021,100,1735689600000,1,1735689600000),(10212,1021,200,1793404800000,0,None),(10311,1031,100,1735689600000,1,None),(10312,1031,300,1793404800000,0,None)]:
            db.execute("INSERT INTO payments(id,priceId,amount,dueDate,isPaid,paidDate,createdAt) VALUES(?,?,?,?,?,?,444)",(id,price,amount,due,paid,date))
        db.execute("INSERT INTO outfitLogs(id,date,note,imageUrls,createdAt,updatedAt) VALUES(101,1735689600000,'原穿搭保留','[]',111,222)")
        db.execute("INSERT INTO outfitItemCrossRef(outfitLogId,itemId) VALUES(101,102)")
        db.commit()
        db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        with sqlite3.connect(args.output / "before-v4.sqlite") as target:
            db.backup(target)
        record = {"tables": snapshot(db), "images": {str(photo): hashlib.sha256(photo.read_bytes()).hexdigest()}}
        (args.output / "before-upgrade.json").write_text(json.dumps(record, ensure_ascii=False, indent=2))
        print("Seeded four fictional items into real v4 simulator database")
    elif args.action == "verify-upgrade":
        record = json.loads((args.output / "before-upgrade.json").read_text())
        for table, expected in record["tables"].items():
            columns = ",".join('"'+c+'"' for c in expected["columns"])
            actual = [list(r) for r in db.execute(f'SELECT {columns} FROM "{table}" ORDER BY rowid')]
            wanted = [list(r) for r in expected["rows"]]
            if table in ('brands', 'categories', 'styles', 'seasons', 'sources', 'locations'):
                index = expected['columns'].index('id')
                ids = {row[index] for row in wanted}
                actual = [row for row in actual if row[index] in ids]
                old = {row[index]: row for row in wanted}
                for row in actual:
                    if is_builtin_blank_fill(table, expected['columns'], old[row[index]], row, args.container):
                        image_index = expected['columns'].index('logoUrl' if table == 'brands' else 'imageUrl')
                        row[image_index] = old[row[index]][image_index]
            for rows in [actual, wanted]:
                for row in rows:
                    for index, column in enumerate(expected["columns"]):
                        if column in ["imageUrls", "sizeChartImageUrl", "imageUrl", "logoUrl"] and row[index]:
                            if column == "imageUrls":
                                row[index] = [Path(path).name for path in json.loads(row[index])]
                            else:
                                row[index] = Path(row[index]).name
            assert actual == wanted, f"Original columns changed: {table}"
        for path, digest in record["images"].items():
            relocated = args.container / "Documents/images" / Path(path).name
            assert hashlib.sha256(relocated.read_bytes()).hexdigest() == digest
        assert db.execute("SELECT purchaseRecordStatus FROM orderBindings WHERE itemId=103").fetchone()[0] == "HISTORICAL_OWNED"
        assert db.execute("SELECT count(*) FROM orderBindings WHERE itemId=104").fetchone()[0] == 0
        assert not db.execute("PRAGMA foreign_key_check").fetchall()
        db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        with sqlite3.connect(args.output / "pre-ui.sqlite") as target:
            db.backup(target)
        result = {"passed": True, "old_tables_compared": 12, "old_image_sha256_preserved": True, "sandbox_paths_relocated": True, "schema": [r[0] for r in db.execute("SELECT identifier FROM grdb_migrations")]}
        (args.output / "upgrade-result.json").write_text(json.dumps(result, ensure_ascii=False, indent=2))
        print(json.dumps(result, ensure_ascii=False))
    else:
        current = db.execute("SELECT p.id,p.totalPrice,p.shipping FROM orderBindings b JOIN prices p ON p.id=b.priceId WHERE b.itemId=101").fetchone()
        assert current and current[1:] == (1200.5,20.0), current
        actual = db.execute("SELECT amount,isPaid,paidDate FROM payments WHERE priceId=?",(current[0],)).fetchall()
        assert len(actual) == 1 and actual[0][0] == 200.25 and actual[0][1] == 1 and actual[0][2] is not None, actual
        assert db.execute("SELECT count(*) FROM orderBindings WHERE itemId=104").fetchone()[0] == 0
        assert db.execute("SELECT purchaseRecordStatus FROM prices WHERE id=1041").fetchone()[0] == "HISTORICAL_OWNED"
        historical = db.execute("SELECT amount,paidDate FROM payments WHERE priceId=1041 AND isPaid=1").fetchall()
        assert historical == [(40.0,None)], historical
        child = db.execute("SELECT id,parentItemId,includedInParentPrice,status FROM items WHERE name='回归·共价小物'").fetchone()
        assert child and child[1:] == (102,1,"PENDING_BALANCE"), child
        assert db.execute("SELECT count(*) FROM prices WHERE itemId=?",(child[0],)).fetchone()[0] == 0
        assert db.execute("SELECT SUM(amount) FROM payments WHERE priceId=1021 AND isPaid=1").fetchone()[0] == 150
        assert db.execute("SELECT isPaid,amount,paidDate FROM payments WHERE id=10212").fetchone() == (0,200.0,None)
        assert db.execute("SELECT paidDate FROM payments WHERE id=10311").fetchone() == (None,)
        assert db.execute("SELECT count(*) FROM prices WHERE itemId=104").fetchone()[0] == 2
        assert not db.execute("PRAGMA foreign_key_check").fetchall()
        assert db.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
        original = json.loads((args.output / "before-upgrade.json").read_text())
        for table, expected in original["tables"].items():
            names = expected["columns"]
            selected = ",".join('"'+name+'"' for name in names)
            actual_rows = [list(row) for row in db.execute(f'SELECT {selected} FROM "{table}" ORDER BY rowid')]
            key_columns = ["outfitLogId", "itemId"] if table == "outfitItemCrossRef" else ["id"]
            indices = [names.index(name) for name in key_columns]
            actual_by_key = {tuple(row[i] for i in indices): row for row in actual_rows}
            for wanted in expected["rows"]:
                actual = actual_by_key[tuple(wanted[i] for i in indices)]
                for index, name in enumerate(names):
                    if table == "items" and name == "status":
                        continue  # Explicit purchasing in the UI changes derived ownership.
                    if name in ["imageUrls", "sizeChartImageUrl", "imageUrl", "logoUrl"]:
                        if name == ('logoUrl' if table == 'brands' else 'imageUrl') and is_builtin_blank_fill(table, names, wanted, actual, args.container):
                            continue
                        def normalized(value):
                            if not value: return value
                            return [Path(p).name for p in json.loads(value)] if name == "imageUrls" else Path(value).name
                        assert normalized(actual[index]) == normalized(wanted[index]), (table,name)
                    else:
                        assert actual[index] == wanted[index], (table,name,actual[index],wanted[index])
        for old, digest in original["images"].items():
            image = args.container / "Documents/images" / Path(old).name
            assert hashlib.sha256(image.read_bytes()).hexdigest() == digest
        result = {"passed": True, "new_order": {"total":1200.5,"shipping":20,"actual_rows":1,"actual":200.25}, "archived_history":{"actual":40,"paid_date":None,"old_orders_retained":2},"shared_accessory":{"own_prices":0,"parent_actual":150},"old_records_preserved_after_ui":True,"original_image_sha256_preserved":True,"original_unpaid_row_preserved":True,"foreign_keys":"ok","integrity":"ok"}
        (args.output / "business-result.json").write_text(json.dumps(result,ensure_ascii=False,indent=2))
        print(json.dumps(result, ensure_ascii=False))
    db.close()

if __name__ == "__main__":
    main()
