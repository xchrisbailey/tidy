#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "$#" != 1 || "$1" != "--unqualified" ]]; then
  echo 'Usage: bash scripts/package-candidate.sh --unqualified' >&2
  echo 'Local development candidate only. Public release is blocked; see docs/distribution.md.' >&2
  exit 2
fi
identity="${TIDY_SIGN_IDENTITY:-DDB64DD6A0BB35AA612980AEDD27B781C6A1E6F0}"
if [[ ! "$identity" =~ ^[[:xdigit:]]{40}$ ]]; then
  echo 'Supply a Developer ID Application certificate SHA-1 via TIDY_SIGN_IDENTITY.' >&2
  exit 2
fi
if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
  echo 'Commit source changes before creating a traceable candidate.' >&2
  exit 2
fi
if ! security find-identity -v -p codesigning | grep -F "$identity \"Developer ID Application:" > /dev/null; then
  echo 'The selected hash is not an available Developer ID Application identity.' >&2
  exit 2
fi
source_revision="$(git rev-parse HEAD)"
swift build --configuration release --arch arm64 --disable-automatic-resolution
bin_path="$(swift build --configuration release --arch arm64 --show-bin-path)"
mkdir -p .build/direct-download
out="$(mktemp -d "$PWD/.build/direct-download/unqualified-${source_revision:0:12}.XXXXXX")"
payload="$out/Tidy-Unqualified-Development"
app="$payload/Tidy Unqualified Development.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_path/Tidy" "$app/Contents/MacOS/"
bash scripts/package-inspection.sh "$bin_path" "$app"
while IFS= read -r -d '' bundle; do
  cp -R "$bundle" "$app/Contents/Resources/"
done < <(find "$bin_path" -maxdepth 1 -type d -name '*.bundle' -print0)
cp -R Packaging/Notices "$app/Contents/Resources/"
cp Packaging/Icons/Tidy.icns "$app/Contents/Resources/"
if ! find "$app/Contents/Resources" -name '*.metallib' -print -quit | grep -q .; then
  echo 'Missing compiled Metal resources; candidate packaging stopped.' >&2
  exit 1
fi
cp Packaging/Info.plist "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName Tidy Unqualified Development' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleDisplayName string Tidy Unqualified Development' "$app/Contents/Info.plist"
# Keep the real sandbox/bookmark identity for qualification; do not imply isolation
# from an existing development install. Sign nested code before the containing app.
service="$app/Contents/XPCServices/dev.tidy.inspection.xpc"
codesign --force --options runtime --timestamp --sign "$identity" "$service/Contents/Helpers/TidyInspectionHelper"
codesign --force --options runtime --timestamp --sign "$identity" "$service"
codesign --force --options runtime --timestamp --sign "$identity" --entitlements Packaging/Tidy.entitlements "$app"
codesign --verify --deep --strict --verbose=2 "$app"
python3 scripts/check-app-icon.py "$app"
codesign --display --verbose=4 "$app" 2> "$out/signature.txt"
codesign --display --entitlements :- "$app" > "$out/entitlements.plist"
cp docs/install.md "$payload/READ-ME-FIRST.md"
cp docs/distribution.md "$payload/distribution.md"
cp -R docs/verification "$payload/verification"
{
  echo 'PUBLIC RELEASE BLOCKED; SUPPORTED HARDWARE: NONE QUALIFIED'
  echo 'Not notarized. No clean-user or native GUI acceptance claimed.'
  echo "Source: $source_revision"
  echo "Identity SHA-1: $identity"
  echo 'Configuration: release; architecture: arm64; hardened runtime; secure timestamp'
  sw_vers
  xcodebuild -version
  swift --version
  shasum -a 256 Package.resolved Packaging/Tidy.entitlements
} > "$payload/BUILD.txt"
# File hashes identify this signed bundle. Signing timestamps and ZIP metadata
# mean this is repeatable packaging, not bit reproducibility.
find "$app" -type f ! -path '*/_CodeSignature/*' -exec shasum -a 256 {} \; > "$out/bundle-sha256.txt"
if [[ "$(git rev-parse HEAD)" != "$source_revision" || -n "$(git status --porcelain --untracked-files=normal)" ]]; then
  echo 'Source changed during packaging; no candidate ZIP will be created.' >&2
  exit 1
fi
ditto -c -k --sequesterRsrc --keepParent "$payload" "$out/Tidy-Unqualified-Development-arm64.zip"
shasum -a 256 "$out/Tidy-Unqualified-Development-arm64.zip" > "$out/SHA256SUMS"
echo "Local unqualified candidate: $out"
