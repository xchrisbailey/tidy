#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/model-smoke.sh --package-only
app="$PWD/.build/TidyInspectionSmoke.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/TidyModelSmoke.app/Contents/MacOS/TidyModelSmoke "$app/Contents/MacOS/"
bash scripts/package-inspection.sh "$(swift build --show-bin-path)" "$app"
cp .build/TidyModelSmoke.app/Contents/Info.plist "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier dev.tidy.inspection-smoke' "$app/Contents/Info.plist"
codesign --force --sign - --entitlements Packaging/InspectionSmoke.entitlements "$app"
codesign --verify --deep --strict "$app"
"$app/Contents/MacOS/TidyModelSmoke" --inspection-only
if [[ "${1:-}" == "--fixture-workers" ]]; then
  swift build --product TidyInspectionTestWorker
  service="$app/Contents/XPCServices/dev.tidy.inspection.xpc"
  cp "$(swift build --show-bin-path)/TidyInspectionTestWorker" "$service/Contents/Helpers/TidyInspectionHelper"
  codesign --force --sign - "$service/Contents/Helpers/TidyInspectionHelper"
  codesign --force --sign - "$service"
  codesign --force --sign - --entitlements Packaging/InspectionSmoke.entitlements "$app"
  for mode in hang cancel oversize crash malformed badText containment; do
    "$app/Contents/MacOS/TidyModelSmoke" --inspection-only --worker-case "$mode"
    python3 - "$service/Contents/Helpers/TidyInspectionHelper" <<'PY'
import subprocess, sys
commands = subprocess.check_output(["ps", "-axo", "command="], text=True).splitlines()
assert not any(line.startswith(sys.argv[1] + " ") or line == sys.argv[1] for line in commands), "parser worker remains alive"
PY
  done
  "$app/Contents/MacOS/TidyModelSmoke" --inspection-only --worker-case disconnect &
  parent=$!
  python3 - "$service/Contents/Helpers/TidyInspectionHelper" <<'PY'
import subprocess, sys, time
for _ in range(100):
    commands = subprocess.check_output(["ps", "-axo", "command="], text=True).splitlines()
    if any(line.startswith(sys.argv[1] + " ") for line in commands):
        break
    time.sleep(0.005)
else:
    raise AssertionError("disconnect probe did not start a parser")
PY
  wait "$parent"
  python3 - "$service/Contents/Helpers/TidyInspectionHelper" <<'PY'
import subprocess, sys, time
for _ in range(100):
    commands = subprocess.check_output(["ps", "-axo", "command="], text=True).splitlines()
    if not any(line.startswith(sys.argv[1] + " ") for line in commands):
        break
    time.sleep(0.02)
else:
    raise AssertionError("parser remains after abrupt parent exit")
print("Packaged abrupt-parent-exit cleanup passed")
PY
fi
