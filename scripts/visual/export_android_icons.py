#!/usr/bin/env python3
"""Run Android's unmodified geometry with a headless recording adapter. No Android sources are edited."""
from pathlib import Path
import subprocess,json,hashlib
root=Path(__file__).resolve().parents[2];android=root.parent/'lolita/app/src/main/java/com/lolita/app/ui/theme/skin/icon'
cache=Path.home()/'.gradle/caches/modules-2/files-2.1';work=root/'.build/icon-export';work.mkdir(parents=True,exist_ok=True)
def jar(group,artifact):
    files=sorted((cache/group/artifact).glob('*/*/*.jar'),reverse=True)
    if not files:raise SystemExit(f'Missing cached Kotlin dependency: {group}/{artifact}')
    return files[0]
jars=[jar('org.jetbrains.kotlin',x) for x in ['kotlin-compiler-embeddable','kotlin-stdlib','kotlin-script-runtime','kotlin-reflect']]+[jar('org.jetbrains.intellij.deps','trove4j'),jar('org.jetbrains','annotations'),jar('org.jetbrains.kotlinx','kotlinx-coroutines-core-jvm')]
java=Path('/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/java')
files=[android/f'Polished{x}.kt' for x in ['ActionDrawings','ContentIcons','DirectionStatusDrawings','NavigationIcons','ControlIcons','LaboratoryIcon']]+[android/'IconKey.kt']
subprocess.run([str(java),'-cp',':'.join(map(str,jars)),'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler','-no-stdlib','-no-reflect','-jvm-target','17','-classpath',':'.join(map(str,jars[1:])),'-d',str(work/'classes'),*map(str,files),*map(str,(root/'scripts/visual/icon-export').glob('*.kt'))],check=True)
raw=subprocess.check_output([str(java),'-Djava.awt.headless=true','-cp',str(work/'classes')+':'+str(jars[1]),'com.lolita.app.ui.theme.skin.icon.MainKt'])
data=json.loads(raw);assert len(data)==7 and all(len(icons)==52 for icons in data.values())
folder=root/'Sources/Resources/skin-art';(folder/'skin-icons.json').write_text(json.dumps(data,separators=(',',':'))+'\n')
(folder/'source-manifest.json').write_text(json.dumps({'android_source_sha256':{f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in files},'background_sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(folder.glob('bg_art_*.png'))},'exporter':'scripts/visual/export_android_icons.py','styles':7,'icons_per_style':52},indent=2)+'\n')
print(f'Exported {sum(map(len,data.values()))} original vector icons')
