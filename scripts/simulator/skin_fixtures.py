#!/usr/bin/env python3
"""Verify a visual-only upgrade has changed no business rows or image bytes."""
import json,sqlite3,sys
from pathlib import Path
from look_fixtures import snapshot,hashes
mode,container,output=sys.argv[1],Path(sys.argv[2]),Path(sys.argv[3])
assert mode=='verify' and '/CoreSimulator/Devices/' in str(container.resolve())
with sqlite3.connect(container/'Documents/lolita.sqlite') as db:
    original=json.loads((output/'v8-original.json').read_text())
    actual=snapshot(db,container)
    assert original==actual,'Visual upgrade changed business data'
    assert db.execute('PRAGMA integrity_check').fetchone()[0]=='ok'
    assert db.execute('PRAGMA foreign_key_check').fetchall()==[]
    images=json.loads((output/'original-image-hashes.json').read_text())
    assert images==hashes(container/'Documents/images'),'Visual upgrade changed image files'
    result=dict(passed=True,tables=len(original),rows=sum(len(x['rows']) for x in original.values()),original_image_files=len(images),business_data_unchanged=True,image_bytes_unchanged=True,integrity='ok',foreign_keys='ok')
    (output/'preservation-result.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result,ensure_ascii=False))
