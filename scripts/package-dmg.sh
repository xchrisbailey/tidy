#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "$#" != 2 || ( "$1" != --unqualified && "$1" != --experimental-beta ) ]]; then
  echo 'Usage: bash scripts/package-dmg.sh --unqualified|--experimental-beta /path/to/signed-candidate.zip' >&2
  echo 'Creates a local candidate DMG only. It never uploads or publishes.' >&2
  exit 2
fi
flavor=unqualified
payload_name=Tidy-Unqualified-Development
app_name='Tidy Unqualified Development'
if [[ "$1" == --experimental-beta ]]; then
  flavor=experimental-beta
  payload_name=Tidy-Experimental-Beta
  app_name='Tidy Beta'
fi
identity="${TIDY_SIGN_IDENTITY:-DDB64DD6A0BB35AA612980AEDD27B781C6A1E6F0}"
if [[ ! "$identity" =~ ^[[:xdigit:]]{40}$ ]]; then
  echo 'Supply an authorized Developer ID Application certificate SHA-1.' >&2
  exit 2
fi
if ! security find-identity -v -p codesigning | grep -F "$identity \"Developer ID Application:" > /dev/null; then
  echo 'The selected Developer ID Application signing identity is unavailable.' >&2
  exit 2
fi
archive="$(python3 -c 'from pathlib import Path; import sys; print(Path(sys.argv[1]).resolve(strict=True))' "$2")"
archive_sha="$(shasum -a 256 "$archive" | awk '{print $1}')"

# Validate archive paths before ditto writes anything; source images are not arbitrary installers.
source_revision="$(python3 - "$archive" "$payload_name" "$flavor" <<'PY'
from pathlib import PurePosixPath
import posixpath, re, stat, sys, zipfile
payload, flavor = sys.argv[2:]
with zipfile.ZipFile(sys.argv[1]) as archive:
    entries = archive.infolist()
    if sum(entry.file_size for entry in entries) > 1 << 30:
        raise SystemExit('Candidate exceeds the app-only archive limit; do not include model weights.')
    names, links = set(), set()
    for entry in entries:
        path = PurePosixPath(entry.filename)
        if (path.is_absolute() or '..' in path.parts or '\\' in entry.filename
                or not path.parts or path.parts[0] not in {payload, '__MACOSX'}):
            raise SystemExit('Unsafe or unexpected archive path.')
        canonical = str(path)
        if canonical.casefold() in names:
            raise SystemExit('Duplicate/case-aliased archive entry.')
        names.add(canonical.casefold())
        if stat.S_ISLNK(entry.external_attr >> 16):
            if entry.file_size > 4096:
                raise SystemExit('Unexpected symlink length.')
            target = archive.read(entry).decode('utf-8')
            resolved = posixpath.normpath(posixpath.join(str(path.parent), target))
            if (target.startswith('/') or '\\' in target or resolved.split('/')[0] != path.parts[0]):
                raise SystemExit('Escaping archive symlink.')
            links.add(canonical.casefold())
    for entry in entries:
        if any(str(parent).casefold() in links for parent in PurePosixPath(entry.filename).parents):
            raise SystemExit('Archive writes through a symlink.')
    build = archive.read(payload + '/BUILD.txt').decode('utf-8')
    if flavor == 'experimental-beta' and 'Packaging flavor: experimental-beta' not in build.splitlines():
        raise SystemExit('Missing experimental-beta provenance; do not relabel an older candidate.')
    match = re.search(r'^Source: ([0-9a-f]{40})$', build, re.MULTILINE)
    if not match:
        raise SystemExit('Missing candidate source provenance.')
    print(match.group(1))
PY
)"
git cat-file -e "$source_revision^{commit}"
mkdir -p .build/direct-download
out="$(mktemp -d "$PWD/.build/direct-download/dmg-${flavor}-${source_revision:0:12}.XXXXXX")"
ditto -x -k "$archive" "$out/extracted"
source_app="$out/extracted/$payload_name/$app_name.app"
[[ -d "$source_app" && ! -L "$source_app" ]]
codesign --verify --deep --strict "$source_app"
codesign --display --verbose=4 "$source_app" 2> "$out/input-signature.txt"
grep -Fx 'TeamIdentifier=5U2B7W5F39' "$out/input-signature.txt" > /dev/null
grep -Fx 'Identifier=dev.xchrisbailey.Tidy' "$out/input-signature.txt" > /dev/null
grep -F 'Authority=Developer ID Application:' "$out/input-signature.txt" > /dev/null
grep -E 'flags=.*runtime' "$out/input-signature.txt" > /dev/null
if [[ "$flavor" == experimental-beta ]]; then
  # Outer ZIP metadata is unsigned. Require the beta identity/source and license
  # inside the verified code-signature seal before accepting a beta for imaging.
  python3 - "$source_app" "$source_revision" <<'PY'
from pathlib import Path
import json, plistlib, sys
app, source = Path(sys.argv[1]), sys.argv[2]
try:
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    record = json.loads((app / 'Contents/Resources/Tidy-BUILD.json').read_text())
    valid = (info.get('CFBundleName') == 'Tidy Beta'
        and info.get('CFBundleDisplayName') == 'Tidy Beta'
        and record == {'schemaVersion': 1, 'applicationSource': source,
            'packagingFlavor': 'experimental-beta', 'releaseTag': 'v0.1.0-beta.1'}
        and (app / 'Contents/Resources/Tidy-LICENSE.txt').read_bytes() == Path('LICENSE').read_bytes())
except (OSError, ValueError):
    valid = False
if not valid:
    raise SystemExit('Missing or inconsistent signed experimental-beta metadata/license.')
PY
fi

payload="$out/payload"
mkdir "$payload"
ditto "$source_app" "$payload/$app_name.app"
ln -s /Applications "$payload/Applications"
cat > "$payload/README.txt" <<TEXT
$app_name — $flavor direct-download candidate

Drag the app to Applications after quitting any other Tidy build. Open normally.
Use only disposable, backed-up test files; no hardware is formally qualified.
Notarization/Gatekeeper acceptance does not establish product or hardware quality.
Do not disable Gatekeeper or strip quarantine to make an installation check pass.

Local Model Setup requires consent for an approximately 2.28 GB model download.
The model is not included in this image. No account, payment or cloud inference.
This is a direct-download app, not an App Store listing or purchase.

Existing Tidy builds share the dev.xchrisbailey.Tidy app identity and storage.
Do not delete its container or erase history/models to make an installation pass.
Undo is best-effort, not a backup. Back up files before organizing real folders.
TEXT
image_name="Tidy-Unqualified-${source_revision:0:7}-arm64.dmg"
if [[ "$flavor" == experimental-beta ]]; then
  image_name=Tidy-0.1.0-beta.1-arm64.dmg
  cp "$out/extracted/$payload_name/BETA-NOTES.md" "$payload/BETA-NOTES.md"
  cp "$out/extracted/$payload_name/LICENSE.txt" "$payload/LICENSE.txt"
fi
python3 - "$out" "$archive_sha" "$source_revision" "$image_name" "$(git rev-parse HEAD)" "$0" "$flavor" <<'PY'
from pathlib import Path
import datetime, hashlib, json, sys
out, archive_sha, revision, image, packager_revision, script, flavor = sys.argv[1:]
manifest = {'schemaVersion': 1, 'applicationSource': revision,
    'sourceArchiveSHA256': archive_sha, 'imageName': image,
    'packagerRevision': packager_revision,
    'packagerScriptSHA256': hashlib.sha256(Path(script).read_bytes()).hexdigest(),
    'createdAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'format': 'UDZO', 'fileSystem': 'HFS+', 'team': '5U2B7W5F39',
    'packagingFlavor': flavor,
    'publicReleaseApproved': False, 'notarySubmittedAtPackaging': False}
Path(out, 'DMG_BUILD.json').write_text(json.dumps(manifest, indent=2) + '\n')
PY
cp "$out/DMG_BUILD.json" "$payload/BUILD.json"
image="$out/$image_name"
hdiutil create -quiet -fs HFS+ -format UDZO -volname "$app_name" -srcfolder "$payload" "$image"
codesign --timestamp --sign "$identity" --identifier dev.xchrisbailey.Tidy.dmg "$image"
codesign --verify --strict "$image"
hdiutil verify "$image" > "$out/image-verification.txt"
[[ "$(shasum -a 256 "$archive" | awk '{print $1}')" == "$archive_sha" ]]
shasum -a 256 "$image" > "$out/SHA256SUMS.before-notarization"
echo "Local $flavor DMG: $out"
echo 'No app installed/launched, notarization submitted, or public release created.'
