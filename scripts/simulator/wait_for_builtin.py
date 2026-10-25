#!/usr/bin/env python3
"""Wait for the shipping initializer's durable local marker before fixture checks."""
import plistlib,sys,time
from pathlib import Path
container=Path(sys.argv[1])
assert '/CoreSimulator/Devices/' in str(container.resolve())
preferences=container/'Library/Preferences/com.lolita.ios.plist'
for _ in range(200):
    try:
        if plistlib.loads(preferences.read_bytes()).get('builtinLibrary.initialized.v1') is True:break
    except (OSError,plistlib.InvalidFileException):pass
    time.sleep(.1)
else:raise SystemExit('Built-in initialization did not finish; do not seed or verify partial startup data')
