#!/usr/bin/env python3
"""Copy current Android offline defaults verbatim; preserve names and provenance."""
from pathlib import Path
import hashlib,json,re,shutil
root=Path(__file__).resolve().parents[2]
android=root.parent/'lolita/app/src/main'
source=android/'java/com/lolita/app/data/repository/BrandRepository.kt'
text=source.read_text()
block=text.split('val presetNames = listOf(',1)[1].split('\n        )',1)[0]
names=re.findall(r'"([^"\n]*)"',block)
assert len(names)>150 and len(set(names))==len(names)
preset=root/'Sources/Data/Preset/PresetData.swift'
swift=preset.read_text()
marker='    // Current Android BrandRepository.ensurePresetBrands; regenerate with sync_builtin_library.py.\n'
start=swift.index(marker) if marker in swift else swift.index('    static let brands: [String] = [')
end=swift.index('\n    ]',start)+len('\n    ]')
swift=swift[:start]+marker+'    static let brands: [String] = [\n'+''.join('        '+json.dumps(name,ensure_ascii=False)+',\n' for name in names)+'    ]'+swift[end:]
preset.write_text(swift)
target=root/'Sources/Resources/builtin'
shutil.copytree(android/'assets/builtin',target,dirs_exist_ok=True)
manifest={'formatVersion':1,'brandSource':'java/com/lolita/app/data/repository/BrandRepository.kt','brandSourceSHA256':hashlib.sha256(source.read_bytes()).hexdigest(),'presetBrands':len(names),'assets':{str(p.relative_to(target)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(target.rglob('*')) if p.is_file() and p.name!='source-manifest.json'}}
(target/'source-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
print('Copied',len(manifest['assets']),'assets; Android preset brands:',len(names))
