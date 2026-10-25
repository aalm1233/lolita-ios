#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$project_root"
run_stamp="$(date +%Y%m%d-%H%M%S)"
output="$project_root/.build/wardrobe-ui-$run_stamp"
mkdir -p "$output/baseline-source"
baseline_ref="${LOLITA_LEDGER_BASELINE_REF:-788fb8d}"
device_id="$(xcrun simctl create "Lolita Wardrobe UI $run_stamp" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro com.apple.CoreSimulator.SimRuntime.iOS-26-5)"
printf '%s\n' "$device_id" > "$output/device-id"
cleanup() {
    xcrun simctl shutdown "$device_id" > /dev/null 2>&1 || true
    printf 'Simulator retained: %s\nResults: %s\n' "$device_id" "$output"
}
trap cleanup EXIT
xcrun simctl boot "$device_id"
xcrun simctl bootstatus "$device_id" -b > "$output/boot.log" 2>&1
xcrun simctl status_bar "$device_id" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
signing=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGNING_ALLOWED=YES)
packages=(-clonedSourcePackagesDirPath "$project_root/.build/derivedData/SourcePackages" -disableAutomaticPackageResolution -skipPackageUpdates)
destination="platform=iOS Simulator,id=$device_id"
git archive "$baseline_ref" | tar -x -C "$output/baseline-source"
xcodebuild -project "$output/baseline-source/Lolita.xcodeproj" -scheme Lolita -configuration Debug -destination "$destination" -derivedDataPath "$output/baseline-build" "${packages[@]}" "${signing[@]}" build > "$output/baseline-build.log" 2>&1
xcrun simctl install "$device_id" "$output/baseline-build/Build/Products/Debug-iphonesimulator/Lolita.app"
xcrun simctl launch "$device_id" com.lolita.ios
container="$(xcrun simctl get_app_container "$device_id" com.lolita.ios data)"
python3 - "$container" <<'PY'
from pathlib import Path
import sqlite3,sys,time
path=Path(sys.argv[1])/'Documents/lolita.sqlite'
for _ in range(150):
    if path.is_file():
        try:
            with sqlite3.connect(path) as db:
                if db.execute('SELECT COUNT(*) FROM brands').fetchone()[0]>0:
                    break
        except sqlite3.Error:
            pass
    time.sleep(.1)
else:
    raise SystemExit('Old application did not finish initializing')
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
path=Path(sys.argv[1])/'Documents/lolita.sqlite'
for _ in range(150):
    if path.is_file():
        with sqlite3.connect(path) as db:
            if db.execute("SELECT COUNT(*) FROM grdb_migrations WHERE identifier='v7-wardrobe-storage'").fetchone()[0]==1:
                break
    time.sleep(.1)
else:
    raise SystemExit('Upgrade migration did not complete')
PY
python3 scripts/simulator/wait_for_builtin.py "$container"
python3 scripts/simulator/ledger_fixtures.py verify-upgrade "$container" "$output"
python3 scripts/simulator/wardrobe_fixtures.py prepare-current "$container" "$output"
xcrun simctl addmedia "$device_id" "$output/picker-a.png" "$output/picker-b.png"
xcodebuild -project Lolita.xcodeproj -scheme Lolita-Ledger-UI -configuration Debug -destination "$destination" -derivedDataPath .build/derivedData "${packages[@]}" "${signing[@]}" -parallel-testing-enabled NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 -maximum-test-execution-time-allowance 240 -only-testing:LolitaUITests/WardrobeUITests -skip-testing:LolitaUITests/WardrobeUITests/test09DarkLargeTextNewRegistrationWithActualKeyboard -resultBundlePath "$output/native-ui.xcresult" test-without-building > "$output/native-ui.log" 2>&1
xcrun simctl ui "$device_id" appearance dark
xcrun simctl ui "$device_id" content_size accessibility-extra-large
xcrun simctl ui "$device_id" content_size > "$output/system-text-size.txt"
xcodebuild -project Lolita.xcodeproj -scheme Lolita-Ledger-UI -configuration Debug -destination "$destination" -derivedDataPath .build/derivedData "${packages[@]}" "${signing[@]}" -parallel-testing-enabled NO -only-testing:LolitaUITests/WardrobeUITests/test09DarkLargeTextNewRegistrationWithActualKeyboard -resultBundlePath "$output/large-text-ui.xcresult" test-without-building > "$output/large-text-ui.log" 2>&1
xcrun simctl ui "$device_id" content_size large
xcrun simctl ui "$device_id" appearance light
xcodebuild -project Lolita.xcodeproj -scheme Lolita-Ledger-UI -configuration Debug -destination "$destination" -derivedDataPath .build/derivedData "${packages[@]}" "${signing[@]}" -parallel-testing-enabled NO -only-testing:LolitaUITests/OrderLedgerUITests/test04ColdRelaunchPreservesHistoricalUnknownDate -resultBundlePath "$output/native-history.xcresult" test-without-building > "$output/native-history.log" 2>&1
xcrun simctl terminate "$device_id" com.lolita.ios > /dev/null 2>&1 || true
container="$(xcrun simctl get_app_container "$device_id" com.lolita.ios data)"
printf '%s\n' "$container" > "$output/app-data-path"
python3 scripts/simulator/wardrobe_fixtures.py verify-results "$container" "$output"
xcrun xcresulttool export attachments --path "$output/native-ui.xcresult" --output-path "$output/screenshots" > "$output/attachments.log" 2>&1
xcrun xcresulttool export attachments --path "$output/large-text-ui.xcresult" --output-path "$output/large-text-screenshots" > "$output/large-text-attachments.log" 2>&1
xcrun xcresulttool export attachments --path "$output/native-history.xcresult" --output-path "$output/history-screenshots" > "$output/history-attachments.log" 2>&1
