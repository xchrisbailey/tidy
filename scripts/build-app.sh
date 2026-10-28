#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build --configuration debug --arch arm64
bin_path="$(swift build --configuration debug --arch arm64 --show-bin-path)"
app="$PWD/.build/Tidy.app"
mkdir -p "$app/Contents/MacOS"
cp "$bin_path/Tidy" "$app/Contents/MacOS/Tidy"
cp Packaging/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - --entitlements Packaging/Tidy.entitlements "$app"
codesign --verify --strict "$app"
echo "Built sandboxed arm64 app: $app"
