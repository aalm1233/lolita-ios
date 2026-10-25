#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$project_root"
output="$project_root/.build/skin-ui-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$output"
printf '%s\n' "$output" > .build/latest-skin-ui-path
source_container="${LOLITA_SKIN_V8_CONTAINER:-$(cat .build/import-ui-work/app-data-path)}"
device_id="$(xcrun simctl create "Lolita Skin UI $(date +%H%M%S)" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro com.apple.CoreSimulator.SimRuntime.iOS-26-5)"
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
python3 scripts/simulator/look_fixtures.py copy-v8 "$container" "$output" "$source_container"
printf '%s\n' "$container" > "$output/app-data-path"
for appearance in light dark; do
    xcrun simctl ui "$device_id" appearance "$appearance"
    xcodebuild -project Lolita.xcodeproj -scheme Lolita-Ledger-UI -configuration Debug -destination "$destination" -derivedDataPath .build/derivedData "${packages[@]}" "${signing[@]}" -parallel-testing-enabled NO -test-timeouts-enabled YES -default-test-execution-time-allowance 600 -maximum-test-execution-time-allowance 720 -only-testing:LolitaUITests/SkinVisualUITests -skip-testing:LolitaUITests/SkinVisualUITests/test03SystemAccessibilityTextWithDarkArtwork -skip-testing:LolitaUITests/SkinVisualUITests/test05FinalSkinScreenshots -resultBundlePath "$output/$appearance-ui.xcresult" test-without-building > "$output/$appearance-ui.log" 2>&1
    xcrun xcresulttool export attachments --path "$output/$appearance-ui.xcresult" --output-path "$output/$appearance-screenshots" > "$output/$appearance-attachments.log" 2>&1
done
xcrun simctl ui "$device_id" appearance dark
xcrun simctl ui "$device_id" content_size accessibility-extra-large
xcodebuild -project Lolita.xcodeproj -scheme Lolita-Ledger-UI -configuration Debug -destination "$destination" -derivedDataPath .build/derivedData "${packages[@]}" "${signing[@]}" -parallel-testing-enabled NO -only-testing:LolitaUITests/SkinVisualUITests/test03SystemAccessibilityTextWithDarkArtwork -resultBundlePath "$output/large-text-ui.xcresult" test-without-building > "$output/large-text-ui.log" 2>&1
xcrun xcresulttool export attachments --path "$output/large-text-ui.xcresult" --output-path "$output/large-text-screenshots" > "$output/large-text-attachments.log" 2>&1
xcrun simctl ui "$device_id" appearance light
xcrun simctl ui "$device_id" content_size large
xcrun simctl terminate "$device_id" com.lolita.ios > /dev/null 2>&1 || true
container="$(xcrun simctl get_app_container "$device_id" com.lolita.ios data)"
printf '%s\n' "$container" > "$output/app-data-path"
python3 scripts/simulator/skin_fixtures.py verify "$container" "$output"
