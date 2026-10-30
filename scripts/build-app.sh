#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build --configuration debug --arch arm64
bin_path="$(swift build --configuration debug --arch arm64 --show-bin-path)"
app="$PWD/.build/Tidy.app"
mkdir -p "$app/Contents/MacOS"
cp "$bin_path/Tidy" "$app/Contents/MacOS/Tidy"
bash scripts/package-inspection.sh "$bin_path" "$app"
mkdir -p "$app/Contents/Resources"
# MLX's compiled Metal library lives in a SwiftPM resource bundle, not in the executable.
while IFS= read -r -d '' bundle; do
  cp -R "$bundle" "$app/Contents/Resources/"
done < <(find "$bin_path" -maxdepth 1 -type d -name '*.bundle' -print0)
cp -R Packaging/Notices "$app/Contents/Resources/"
cp LICENSE "$app/Contents/Resources/Tidy-LICENSE.txt"
cp Packaging/Icons/Tidy.icns "$app/Contents/Resources/"
if ! find "$app/Contents/Resources" -name '*.metallib' -print -quit | grep -q .; then
  echo "Missing MLX Metal resources. Build with the Xcode toolchain before packaging." >&2
  exit 1
fi
cp Packaging/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - --entitlements Packaging/Tidy.entitlements "$app"
codesign --verify --deep --strict "$app"
python3 scripts/check-app-icon.py "$app"
echo "Built sandboxed arm64 app: $app"
