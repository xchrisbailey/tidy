#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "$#" -gt 1 || ( "$#" == 1 && "$1" != "--without-service" ) ]]; then
  echo 'Usage: bash scripts/release-tests.sh [--without-service]' >&2
  exit 2
fi
identity="${TIDY_SIGN_IDENTITY:-DDB64DD6A0BB35AA612980AEDD27B781C6A1E6F0}"
if [[ ! "$identity" =~ ^[[:xdigit:]]{40}$ ]] ||
  ! security find-identity -v -p codesigning | grep -F "$identity \"Developer ID Application:" > /dev/null; then
  echo 'Select an available authorized Developer ID Application certificate SHA-1.' >&2
  exit 2
fi
developer="$(xcode-select -p)"
swift_bin="$(xcrun --find swift)"
toolchain="$(dirname "$(dirname "$swift_bin")")"
runner="$toolchain/libexec/swift/pm/swiftpm-testing-helper"
platform="$developer/Platforms/MacOSX.platform/Developer"
test -x "$runner"
mkdir -p .build/release-tests
out="$(mktemp -d "$PWD/.build/release-tests/host.XXXXXX")"
swift build --configuration release --disable-automatic-resolution
bin_path="$(swift build --configuration release --show-bin-path)"
mkdir -p "$out/production-binaries"
cp "$bin_path/TidyInspectionService" "$bin_path/TidyInspectionHelper" "$out/production-binaries/"
# Link Apple's test-framework search paths into the test image, rather than
# injecting DYLD overrides or disabling hardened runtime library validation.
# Stage the normally linked production service/parser first so test-only linker
# paths cannot leak into their packaged code.
# The UI integration suite imports internal app state; enable testability only here.
swift build --configuration release --build-tests --disable-automatic-resolution \
  -Xswiftc -enable-testing \
  -Xlinker -rpath -Xlinker "$platform/Library/Frameworks" \
  -Xlinker -rpath -Xlinker "$platform/usr/lib"
app="$out/Tidy Unqualified Release Tests.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/PlugIns"
cp "$runner" "$app/Contents/MacOS/swiftpm-testing-helper"
cp -R "$bin_path/TidyCoreTests.xctest" "$app/Contents/PlugIns/"
bundle="$app/Contents/PlugIns/TidyCoreTests.xctest"
test_image="$bundle/Contents/MacOS/TidyCoreTests"
codesign --force --options runtime --timestamp --sign "$identity" "$bundle"
cp Packaging/Info.plist "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable swiftpm-testing-helper' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier dev.tidy.release-tests' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName Tidy Unqualified Release Tests' "$app/Contents/Info.plist"
if [[ "${1:-}" != "--without-service" ]]; then
  bash scripts/package-inspection.sh "$out/production-binaries" "$app"
  service="$app/Contents/XPCServices/dev.tidy.inspection.xpc"
  codesign --force --options runtime --timestamp --sign "$identity" "$service/Contents/Helpers/TidyInspectionHelper"
  codesign --force --options runtime --timestamp --sign "$identity" "$service"
fi
# Match the existing CLI fixture authority: these cases create bookmarks without
# native picker grants. This test-only host does not qualify App Sandbox grants;
# the production app entitlement and independently sandboxed parser are unchanged.
codesign --force --options runtime --timestamp --sign "$identity" "$app"
codesign --verify --deep --strict --verbose=2 "$app"
echo "Optimized test host: $out"
{
  echo 'LOCAL TEST HOST ONLY; PUBLIC RELEASE BLOCKED; NO HARDWARE QUALIFICATION'
  echo "Source: $(git rev-parse HEAD)"
  echo 'Configuration: release; hosted coordinator suite: serial; test cases unchanged'
  echo 'Host authority: unsandboxed CLI fixtures; production parser sandbox unchanged'
  echo "Identity SHA-1: $identity"
  git status --short
  xcodebuild -version
  shasum -a 256 "$test_image" "$app/Contents/MacOS/swiftpm-testing-helper" Package.resolved
} > "$out/BUILD.txt"
"$runner" --test-bundle-path "$bin_path/TidyCoreTests.xctest/Contents/MacOS/TidyCoreTests" \
  --testing-library swift-testing --list-tests > "$out/expected-tests.txt"
"$app/Contents/MacOS/swiftpm-testing-helper" --test-bundle-path "$test_image" \
  --testing-library swift-testing --list-tests > "$out/hosted-tests.txt"
grep -q '^TidyCoreTests\.' "$out/expected-tests.txt"
diff -u "$out/expected-tests.txt" "$out/hosted-tests.txt"
if [[ "${1:-}" == "--without-service" ]]; then
  # Negative control: the unchanged OCR cases must fail without the production XPC service.
  "$app/Contents/MacOS/swiftpm-testing-helper" --test-bundle-path "$test_image" --testing-library swift-testing \
    --filter screenshotEvidenceNamesAndReopenedUndoPreservesBytes 2>&1 | tee "$out/negative.log"
  exit 0
fi
# The application runs one task at a time. Suite-wide parallel fixture setup can
# starve the unchanged parser deadlines; explicit in-test concurrency remains intact.
"$app/Contents/MacOS/swiftpm-testing-helper" --test-bundle-path "$test_image" \
  --testing-library swift-testing --no-parallel 2>&1 | tee "$out/core.log"
python3 - "$out" <<'PY'
from pathlib import Path
import re, sys
out = Path(sys.argv[1])
expected = len((out / "expected-tests.txt").read_text().splitlines())
summaries = re.findall(r"Test run with (\d+) tests? in .* passed", (out / "core.log").read_text())
if not summaries or int(summaries[-1]) != expected:
    raise SystemExit("Hosted suite did not report a complete passing discovered test set")
print(f"Hosted optimized coverage: all {expected} discovered coordinator test functions reported")
PY
# These complete suites need no application XPC service. Retain their normal runner,
# including the transfer suite's real local HTTP server rather than widening the host sandbox.
swift test --configuration release --skip-build --disable-automatic-resolution \
  --filter 'ModelSetupTests|ModelTransferTests|WorkerSupervisorTests' 2>&1 | tee "$out/model-supervisor.log"
# UI fixtures use their own windows, temporary files and injected local completions.
swift test --configuration release --skip-build --disable-automatic-resolution \
  --filter 'WorkspaceModelTests|SettingsLifecycleTests|WorkspaceGeometryTests' 2>&1 | tee "$out/workspace.log"
