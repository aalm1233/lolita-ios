#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$project_root"
output="$project_root/.build/builtin-ui-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$output"
printf '%s\n' "$output" > .build/latest-builtin-ui-path
source_container="${LOLITA_BUILTIN_V8_CONTAINER:-$(cat .build/import-ui-work/app-data-path)}"
baseline_app="${LOLITA_BUILTIN_BASELINE_APP:-$project_root/.build/skin-ui-20261025-092410/accessibility-fixed-Lolita.app}"
if [[ ! -d "$baseline_app" || ! -f "$source_container/Documents/lolita.sqlite" ]]; then printf 'Prepare a signed pre-builtin app and a fictional v8 test container.\n' >&2; exit 1; fi
devices=()
cleanup() { for device in "${devices[@]}"; do xcrun simctl shutdown "$device" >/dev/null 2>&1 || true; done; printf 'Results: %s\n' "$output"; }
trap cleanup EXIT
signing=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGNING_ALLOWED=YES)
packages=(-disableAutomaticPackageResolution -skipPackageUpdates)
modes=(fresh upgrade)
if [[ -n "${LOLITA_BUILTIN_MODE:-}" ]]; then
    case "$LOLITA_BUILTIN_MODE" in fresh|upgrade) modes=("$LOLITA_BUILTIN_MODE");; *) printf 'Unknown test mode\n' >&2; exit 1;; esac
fi
built=0
for mode in "${modes[@]}"; do
    target="$output/$mode"; mkdir -p "$target"
    device="$(xcrun simctl create "Lolita Builtin $mode $(date +%H%M%S)" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro com.apple.CoreSimulator.SimRuntime.iOS-26-5)"
    devices+=("$device"); printf '%s\n' "$device" > "$target/device-id"
    xcrun simctl boot "$device"; xcrun simctl bootstatus "$device" -b > "$target/boot.log" 2>&1
    xcrun simctl status_bar "$device" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
    destination="platform=iOS Simulator,id=$device"
    if [[ "$built" == 0 ]]; then
        xcodebuild -project Lolita.xcodeproj -scheme Lolita-Ledger-UI -configuration Debug -destination "$destination" -derivedDataPath .build/derivedData "${packages[@]}" "${signing[@]}" build-for-testing > "$output/ui-build.log" 2>&1
        ditto .build/derivedData/Build/Products/Debug-iphonesimulator/Lolita.app "$output/Lolita.app"
        built=1
    fi
    if [[ "$mode" == upgrade ]]; then
        xcrun simctl ui "$device" appearance dark
        xcrun simctl ui "$device" content_size accessibility-extra-large
        xcrun simctl install "$device" "$baseline_app"
        xcrun simctl launch "$device" com.lolita.ios
        container="$(xcrun simctl get_app_container "$device" com.lolita.ios data)"
        python3 - "$container" <<'PY'
import sqlite3,sys,time
from pathlib import Path
p=Path(sys.argv[1])/'Documents/lolita.sqlite'
for _ in range(150):
    try:
        with sqlite3.connect(p) as db:
            if db.execute('SELECT count(*) FROM brands').fetchone()[0]>0:break
    except sqlite3.Error:pass
    time.sleep(.1)
else:raise SystemExit('Old application failed to initialize')
PY
        xcrun simctl terminate "$device" com.lolita.ios
        python3 scripts/simulator/look_fixtures.py copy-v8 "$container" "$target" "$source_container"
    fi
    xcrun simctl install "$device" "$output/Lolita.app"
    xcodebuild -project Lolita.xcodeproj -scheme Lolita-Ledger-UI -configuration Debug -destination "$destination" -derivedDataPath .build/derivedData "${packages[@]}" "${signing[@]}" -parallel-testing-enabled NO -test-timeouts-enabled YES -default-test-execution-time-allowance 600 -maximum-test-execution-time-allowance 720 -only-testing:LolitaUITests/BuiltInLibraryUITests -resultBundlePath "$target/native-ui.xcresult" test-without-building > "$target/native-ui.log" 2>&1
    xcrun xcresulttool export attachments --path "$target/native-ui.xcresult" --output-path "$target/screenshots" > "$target/attachments.log" 2>&1
    xcrun simctl terminate "$device" com.lolita.ios >/dev/null 2>&1 || true
    container="$(xcrun simctl get_app_container "$device" com.lolita.ios data)"; printf '%s\n' "$container" > "$target/app-data-path"
    python3 scripts/simulator/builtin_fixtures.py "$mode" "$container" "$target"
    xcrun simctl shutdown "$device"
done
