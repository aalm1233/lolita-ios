#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$project_root"
output="$project_root/.build/look-ui-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$output"
printf '%s\n' "$output" > .build/latest-look-ui-path
source_container="${LOLITA_LOOK_V8_CONTAINER:-}"
if [[ -n "$source_container" && ! -f "$source_container/Documents/lolita.sqlite" ]]; then printf 'Missing v8 simulator database: %s\n' "$source_container" >&2; exit 1; fi
if [[ -z "$source_container" && -f .build/import-ui-work/app-data-path ]]; then source_container="$(cat .build/import-ui-work/app-data-path)"; fi
device_id="$(xcrun simctl create "Lolita Look UI $(date +%H%M%S)" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro com.apple.CoreSimulator.SimRuntime.iOS-26-5)"
printf '%s\n' "$device_id" > "$output/device-id"
cleanup() { xcrun simctl shutdown "$device_id" > /dev/null 2>&1 || true; printf 'Simulator retained: %s\nResults: %s\n' "$device_id" "$output"; }
trap cleanup EXIT
xcrun simctl boot "$device_id"
xcrun simctl bootstatus "$device_id" -b > "$output/boot.log" 2>&1
xcrun simctl status_bar "$device_id" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
signing=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGNING_ALLOWED=YES)
packages=(-clonedSourcePackagesDirPath "$project_root/.build/derivedData/SourcePackages" -disableAutomaticPackageResolution -skipPackageUpdates)
destination="platform=iOS Simulator,id=$device_id"
baseline_app="$project_root/.build/wardrobe-ui-20261024-123159/baseline-build/Build/Products/Debug-iphonesimulator/Lolita.app"
if [[ ! -d "$baseline_app" ]]; then
    mkdir -p "$output/baseline-source"
    git archive 788fb8d | tar -x -C "$output/baseline-source"
    xcodebuild -project "$output/baseline-source/Lolita.xcodeproj" -scheme Lolita -configuration Debug -destination "$destination" -derivedDataPath "$output/baseline-build" "${packages[@]}" "${signing[@]}" build > "$output/baseline-build.log" 2>&1
    baseline_app="$output/baseline-build/Build/Products/Debug-iphonesimulator/Lolita.app"
fi
xcrun simctl install "$device_id" "$baseline_app"
xcrun simctl launch "$device_id" com.lolita.ios
container="$(xcrun simctl get_app_container "$device_id" com.lolita.ios data)"
python3 - "$container" <<'PY'
from pathlib import Path
import sqlite3,sys,time
p=Path(sys.argv[1])/'Documents/lolita.sqlite'
for _ in range(150):
    try:
        if p.exists():
            with sqlite3.connect(p) as db:
                if db.execute('SELECT count(*) FROM brands').fetchone()[0]>0:break
    except sqlite3.Error:pass
    time.sleep(.1)
else:raise SystemExit('Old application did not initialize')
PY
xcrun simctl terminate "$device_id" com.lolita.ios
python3 scripts/simulator/ledger_fixtures.py seed-v4 "$container" "$output"
xcodebuild -project Lolita.xcodeproj -scheme Lolita-Ledger-UI -configuration Debug -destination "$destination" -derivedDataPath .build/derivedData "${packages[@]}" "${signing[@]}" build-for-testing > "$output/ui-build.log" 2>&1
xcrun simctl install "$device_id" .build/derivedData/Build/Products/Debug-iphonesimulator/Lolita.app
xcrun simctl launch "$device_id" com.lolita.ios
container="$(xcrun simctl get_app_container "$device_id" com.lolita.ios data)"
python3 - "$container" <<'PY'
from pathlib import Path
import sqlite3,sys,time
p=Path(sys.argv[1])/'Documents/lolita.sqlite'
for _ in range(150):
    try:
        with sqlite3.connect(p) as db:
            if db.execute("SELECT count(*) FROM grdb_migrations WHERE identifier='v8-import-sessions'").fetchone()[0]:break
    except sqlite3.Error:pass
    time.sleep(.1)
else:raise SystemExit('Migration did not finish')
PY
xcrun simctl terminate "$device_id" com.lolita.ios
python3 scripts/simulator/wait_for_builtin.py "$container"
python3 scripts/simulator/ledger_fixtures.py verify-upgrade "$container" "$output"
if [[ -n "$source_container" && -f "$source_container/Documents/lolita.sqlite" ]]; then
python3 scripts/simulator/look_fixtures.py copy-v8 "$container" "$output" "$source_container"
xcrun simctl launch "$device_id" com.lolita.ios
python3 - "$container" <<'PY'
from pathlib import Path
import sqlite3,sys,time,json
root=Path(sys.argv[1]);p=root/'Documents/lolita.sqlite'
for _ in range(150):
    with sqlite3.connect(p) as db:
        paths=db.execute('SELECT imageUrls FROM items WHERE imageUrls<>\'[]\'').fetchall()
        if paths and all(all(str(root) in path for path in json.loads(x[0])) for x in paths):break
    time.sleep(.1)
else:raise SystemExit('Image relocation did not finish')
PY
xcrun simctl terminate "$device_id" com.lolita.ios
else
    python3 scripts/simulator/look_fixtures.py snapshot-v8 "$container" "$output"
fi
python3 scripts/simulator/look_fixtures.py seed "$container" "$output"
printf '%s\n' "$container" > "$output/app-data-path"
xcrun simctl addmedia "$device_id" "$container/Documents/images/look-white.png"
xcodebuild -project Lolita.xcodeproj -scheme Lolita-Ledger-UI -configuration Debug -destination "$destination" -derivedDataPath .build/derivedData "${packages[@]}" "${signing[@]}" -parallel-testing-enabled NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 -maximum-test-execution-time-allowance 240 -only-testing:LolitaUITests/LookDailyUITests -skip-testing:LolitaUITests/LookDailyUITests/test07DarkAccessibilityThemeLookAndShareControls -resultBundlePath "$output/native-ui.xcresult" test-without-building > "$output/native-ui.log" 2>&1
xcrun simctl ui "$device_id" appearance dark
xcrun simctl ui "$device_id" content_size accessibility-extra-large
xcrun simctl ui "$device_id" content_size > "$output/system-text-size.txt"
xcodebuild -project Lolita.xcodeproj -scheme Lolita-Ledger-UI -configuration Debug -destination "$destination" -derivedDataPath .build/derivedData "${packages[@]}" "${signing[@]}" -parallel-testing-enabled NO -only-testing:LolitaUITests/LookDailyUITests/test07DarkAccessibilityThemeLookAndShareControls -resultBundlePath "$output/large-text-ui.xcresult" test-without-building > "$output/large-text-ui.log" 2>&1
xcrun simctl ui "$device_id" appearance light
xcrun simctl ui "$device_id" content_size large
xcrun simctl terminate "$device_id" com.lolita.ios > /dev/null 2>&1 || true
container="$(xcrun simctl get_app_container "$device_id" com.lolita.ios data)"
printf '%s\n' "$container" > "$output/app-data-path"
python3 scripts/simulator/look_fixtures.py verify "$container" "$output"
xcrun xcresulttool export attachments --path "$output/native-ui.xcresult" --output-path "$output/screenshots" > "$output/attachments.log" 2>&1
xcrun xcresulttool export attachments --path "$output/large-text-ui.xcresult" --output-path "$output/large-text-screenshots" > "$output/large-text-attachments.log" 2>&1
