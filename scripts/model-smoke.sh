#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build --product TidyModelSmoke
swift build --product TidyInspectionHelper
bin_path="$(swift build --show-bin-path)"
app="$PWD/.build/TidyModelSmoke.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_path/TidyModelSmoke" "$app/Contents/MacOS/TidyModelSmoke"
cp "$bin_path/TidyInspectionHelper" "$app/Contents/MacOS/TidyInspectionHelper"
# This diagnostic parent is not App Sandbox enabled. The helper still installs its own restrictive
# profile; production packaging uses App Sandbox inheritance in addition to that profile.
codesign --force --sign - "$app/Contents/MacOS/TidyInspectionHelper"
cp Packaging/Info.plist "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable TidyModelSmoke' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier dev.tidy.model-smoke' "$app/Contents/Info.plist"
while IFS= read -r -d '' bundle; do
  cp -R "$bundle" "$app/Contents/Resources/"
done < <(find "$bin_path" -maxdepth 1 -type d -name '*.bundle' -print0)
codesign --force --sign - --entitlements Packaging/ModelSmoke.entitlements "$app"
if [[ "${1:-}" == "--package-only" ]]; then
  exit 0
fi
if [[ "${1:-}" == "--download-approved" ]]; then
  # An explicit developer qualification download, separate from the app's consent UI.
  exec "$app/Contents/MacOS/TidyModelSmoke" --download-approved
fi
# Prove packaged resource discovery without network or the build-machine Metal fallback.
exec sandbox-exec -p "(version 1) (allow default) (deny network*) (deny file-read* (subpath \"$bin_path\"))" \
  "$app/Contents/MacOS/TidyModelSmoke"
