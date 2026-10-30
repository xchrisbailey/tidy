#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$#" != 1 ]]; then
  echo 'Usage: bash scripts/candidate-smoke.sh /absolute/path/to/candidate-output-directory' >&2
  exit 2
fi
out="$(cd "$1" && pwd)"
candidate="$out/Tidy-Unqualified-Development/Tidy Unqualified Development.app"
if [[ -d "$out/Tidy-Experimental-Beta/Tidy Beta.app" ]]; then
  candidate="$out/Tidy-Experimental-Beta/Tidy Beta.app"
fi
test -d "$candidate"
identity="${TIDY_SIGN_IDENTITY:-DDB64DD6A0BB35AA612980AEDD27B781C6A1E6F0}"
bin_path="$(swift build --configuration release --arch arm64 --show-bin-path)"
app="$out/Tidy Unqualified Diagnostic.app"
if [[ -e "$app" ]]; then
  echo 'Diagnostic already exists; retain its evidence rather than overwriting it.' >&2
  exit 2
fi
mkdir -p "$app/Contents/MacOS"
cp "$bin_path/TidyModelSmoke" "$app/Contents/MacOS/"
cp -R "$candidate/Contents/Resources" "$app/Contents/"
cp -R "$candidate/Contents/XPCServices" "$app/Contents/"
cp "$candidate/Contents/Info.plist" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable TidyModelSmoke' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier dev.tidy.model-smoke' "$app/Contents/Info.plist"
codesign --force --options runtime --timestamp --sign "$identity" --entitlements Packaging/ModelSmoke.entitlements "$app"
codesign --verify --deep --strict --verbose=2 "$app"
# This is a diagnostic, not the GUI app or an App Sandbox grant/clean-user check.
# Deny the source build resources and network to exercise the copied Metal library.
exec sandbox-exec -p "(version 1) (allow default) (deny network*) (deny file-read* (subpath \"$bin_path\"))" \
  "$app/Contents/MacOS/TidyModelSmoke"
