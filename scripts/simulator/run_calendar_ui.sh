#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$project_root"
output="$project_root/.build/calendar-ui-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$output"
printf '%s\n' "$output" > .build/latest-calendar-ui-path
source_container="${LOLITA_CALENDAR_V8_CONTAINER:-$(cat .build/builtin-ui-20261025-114002/upgrade/app-data-path)}"
device_id="$(xcrun simctl create "Lolita Calendar UI $(date +%H%M%S)" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro com.apple.CoreSimulator.SimRuntime.iOS-26-5)"
printf '%s\n' "$device_id" > "$output/device-id"
cleanup() { xcrun simctl shutdown "$device_id" > /dev/null 2>&1 || true; printf 'Simulator retained: %s\nResults: %s\n' "$device_id" "$output"; }
trap cleanup EXIT
xcrun simctl boot "$device_id"
xcrun simctl bootstatus "$device_id" -b > "$output/boot.log" 2>&1
xcrun simctl status_bar "$device_id" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
signing=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGNING_ALLOWED=YES)
packages=(-disableAutomaticPackageResolution -skipPackageUpdates)
destination="platform=iOS Simulator,id=$device_id"
xcodebuild -project Lolita.xcodeproj -scheme Lolita-Ledger-UI -configuration Debug -destination "$destination" -derivedDataPath .build/derivedData "${packages[@]}" "${signing[@]}" build-for-testing > "$output/ui-build.log" 2>&1
xcrun simctl install "$device_id" .build/derivedData/Build/Products/Debug-iphonesimulator/Lolita.app
container="$(xcrun simctl get_app_container "$device_id" com.lolita.ios data)"
# Initialize local defaults through the shipping UI before restoring the test snapshot.
# The separate builtin runner verifies first-time installation and upgrade additions.
xcrun simctl launch "$device_id" com.lolita.ios > "$output/initialization.log"
python3 scripts/simulator/wait_for_builtin.py "$container"
xcrun simctl terminate "$device_id" com.lolita.ios
python3 scripts/simulator/look_fixtures.py copy-v8 "$container" "$output" "$source_container"
printf '%s\n' "$container" > "$output/app-data-path"
# Write fixture defaults while cfprefsd is stopped so its cache cannot discard them.
xcrun simctl shutdown "$device_id"
python3 scripts/simulator/calendar_fixtures.py seed "$container" "$output"
xcrun simctl boot "$device_id"
xcrun simctl bootstatus "$device_id" -b >> "$output/boot.log" 2>&1
xcrun simctl status_bar "$device_id" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
ditto .build/derivedData/Build/Products/Debug-iphonesimulator/Lolita.app "$output/Lolita.app"
xcrun simctl ui "$device_id" appearance light
xcodebuild -project Lolita.xcodeproj -scheme Lolita-Ledger-UI -configuration Debug -destination "$destination" -derivedDataPath .build/derivedData "${packages[@]}" "${signing[@]}" -parallel-testing-enabled NO -only-testing:LolitaUITests/PaymentYearUITests -skip-testing:LolitaUITests/PaymentYearUITests/test04DarkAccessibilityGridAndEmptyMonth -skip-testing:LolitaUITests/PaymentYearUITests/test05YearCalendarAcrossSevenSkins -resultBundlePath "$output/native-ui.xcresult" test-without-building > "$output/native-ui.log" 2>&1
xcrun xcresulttool export attachments --path "$output/native-ui.xcresult" --output-path "$output/screenshots" > "$output/attachments.log" 2>&1
for appearance in light dark; do
    xcrun simctl ui "$device_id" appearance "$appearance"
    xcodebuild -project Lolita.xcodeproj -scheme Lolita-Ledger-UI -configuration Debug -destination "$destination" -derivedDataPath .build/derivedData "${packages[@]}" "${signing[@]}" -parallel-testing-enabled NO -only-testing:LolitaUITests/PaymentYearUITests/test05YearCalendarAcrossSevenSkins -resultBundlePath "$output/skins-$appearance-ui.xcresult" test-without-building > "$output/skins-$appearance-ui.log" 2>&1
    xcrun xcresulttool export attachments --path "$output/skins-$appearance-ui.xcresult" --output-path "$output/skins-$appearance-screenshots" > "$output/skins-$appearance-attachments.log" 2>&1
done
xcrun simctl ui "$device_id" appearance dark
xcrun simctl ui "$device_id" content_size accessibility-extra-large
xcodebuild -project Lolita.xcodeproj -scheme Lolita-Ledger-UI -configuration Debug -destination "$destination" -derivedDataPath .build/derivedData "${packages[@]}" "${signing[@]}" -parallel-testing-enabled NO -only-testing:LolitaUITests/PaymentYearUITests/test04DarkAccessibilityGridAndEmptyMonth -resultBundlePath "$output/large-text-ui.xcresult" test-without-building > "$output/large-text-ui.log" 2>&1
xcrun xcresulttool export attachments --path "$output/large-text-ui.xcresult" --output-path "$output/large-text-screenshots" > "$output/large-text-attachments.log" 2>&1
xcrun simctl ui "$device_id" appearance light
xcrun simctl ui "$device_id" content_size large
xcrun simctl terminate "$device_id" com.lolita.ios > /dev/null 2>&1 || true
container="$(xcrun simctl get_app_container "$device_id" com.lolita.ios data)"
printf '%s\n' "$container" > "$output/app-data-path"
python3 scripts/simulator/calendar_fixtures.py verify "$container" "$output"
