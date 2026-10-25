#!/usr/bin/env python3
"""Port Android's existing launcher vector into an opaque iOS icon; no artwork is redesigned."""
from pathlib import Path
import xml.etree.ElementTree as ET
import subprocess,json,re
root=Path(__file__).resolve().parents[2]
resources=root.parent/'lolita/app/src/main/res'
colors={e.attrib['name']:e.text for e in ET.parse(resources/'values/colors.xml').getroot()}
ns='{http://schemas.android.com/apk/res/android}'
paths=[]
for node in ET.parse(resources/'drawable/ic_launcher_foreground.xml').getroot():
    if node.tag!='path':raise SystemExit('Unsupported launcher vector node')
    commands=[];tokens=re.findall(r'[A-Za-z]|[-+]?(?:\d*\.\d+|\d+)',node.attrib[ns+'pathData']);i=0
    while i<len(tokens):
        op=tokens[i];i+=1
        count={'M':2,'L':2,'Q':4,'C':6,'Z':0}.get(op)
        if count is None:raise SystemExit(f'Unsupported vector command: {op}')
        commands.append(dict(op=op,values=list(map(float,tokens[i:i+count]))));i+=count
    def color(value):return colors[value.split('/')[-1]] if value.startswith('@color/') else value
    paths.append(dict(commands=commands,fill=color(node.attrib.get(ns+'fillColor','#00000000')),stroke=color(node.attrib.get(ns+'strokeColor','#00000000')),width=float(node.attrib.get(ns+'strokeWidth','0')),evenOdd=node.attrib.get(ns+'fillType')=='evenOdd'))
work=root/'.build/app-icon';work.mkdir(parents=True,exist_ok=True)
input_path=work/'vector.json';input_path.write_text(json.dumps(dict(background=colors['ic_launcher_background'],paths=paths)))
folder=root/'Sources/Resources/Assets.xcassets/AppIcon.appiconset';folder.mkdir(parents=True,exist_ok=True)
subprocess.run(['/usr/bin/swift',str(root/'scripts/visual/export_app_icon.swift'),str(input_path),str(folder/'AppIcon.png')],check=True)
(folder/'Contents.json').write_text(json.dumps({'images':[{'filename':'AppIcon.png','idiom':'universal','platform':'ios','size':'1024x1024'}],'info':{'author':'xcode','version':1}},indent=2)+'\n')
(folder.parent/'Contents.json').write_text(json.dumps({'info':{'author':'xcode','version':1}},indent=2)+'\n')
