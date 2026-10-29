#!/bin/bash
set -euo pipefail
bin_path="$1"
app="$2"
service="$app/Contents/XPCServices/dev.tidy.inspection.xpc"
mkdir -p "$service/Contents/MacOS"
cp "$bin_path/TidyInspectionService" "$service/Contents/MacOS/"
cp "$bin_path/TidyInspectionHelper" "$service/Contents/MacOS/"
cp Packaging/InspectionService-Info.plist "$service/Contents/Info.plist"
# launchd starts this service independently of the app's sandbox. It installs a stricter
# profile before accepting IPC; its parser child inherits that profile, not the app's grants.
codesign --force --sign - "$service/Contents/MacOS/TidyInspectionHelper"
codesign --force --sign - "$service"
codesign --verify --deep --strict "$service"
# Remove only our previous, generated NSTask-helper artifact when repackaging in place.
rm -f "$app/Contents/MacOS/TidyInspectionHelper"
