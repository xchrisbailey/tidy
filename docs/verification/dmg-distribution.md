# Direct-download DMG packaging and notarization

2026-10-30. Distribution target: a DMG linked from future GitHub Releases/project
page. No Mac App Store submission, GitHub release or website publication.

The owner explicitly approved packaging the tested app, submitting it to Apple's
notary service with dedicated `tidy-notary` credentials, and stapling/verifying.
This is candidate-processing authorization, not a public-release approval or new
hardware/product qualification claim. The three earlier formal native checks
remain owner-deferred; they are not being reintroduced as required wizard reruns.

## Packaging

Application source: `b422b36fa0db7d6eee0e030200d2de7285aa5e36`.
Signed source ZIP SHA-256:
`40ee29c35ae67bdd35323efcb6ca8076c31f33b68ff46edf6855505ec8fd5dea`.
Packager/test implementation: `af0b3fc`.

The CLI integration check first failed because DMG packaging did not exist, then
passed after implementation:

```sh
python3 scripts/test-package-dmg.py .build/direct-download/Tidy-Unqualified-b422b36-arm64.zip
bash scripts/lint.sh
shellcheck scripts/package-dmg.sh
```

The selected verified postcommit packaging run produced
`.build/direct-download/dmg-unqualified-b422b36fa0db.1Am7Dr/Tidy-Unqualified-b422b36-arm64.dmg`.
The tests verified UDZO/read-only image integrity and Developer ID signature,
mounted it read-only, checked the Applications link/readme, compared every app
file/link against the signed ZIP, verified nested signatures, and detached it.
The source app/ZIP remain unchanged; no model weights or notarization credentials
are included. Negative controls reject public-release override flags, unsafe
absolute/traversal paths and escaping archive links before extraction.

The image uses native HFS+/UDZO tooling, without new dependencies or Finder
automation. macOS 27 emits an `hdiutil create` deprecation notice; the compatible
tool succeeds. No installation, app launch or native/clean-user gate is claimed
from the mounted-image checks.

## Apple submission

One owner-approved submission was started using:

```sh
xcrun notarytool submit EXACT_IMAGE_PATH --keychain-profile tidy-notary --wait --timeout 20m --output-format json
```

The wrapper preserves request/source/pre-staple hash, receipt and safe status in
ignored local `.build/notarization/` records. Passwords are read only by Apple's
tool from Keychain; no credential discovery or secret export occurs. A wait
timeout does not cancel Apple's job or authorize a duplicate submission.

**Apple result: Accepted**, completed `2026-10-30T04:03:57Z`.
Submission ID: `d4718e71-5198-40a6-a134-3ac7e532b3fb`.
The retrieved Apple log reports zero issues. The original submitted image remains
unchanged. A separate copy was stapled and validated following Apple's
[outermost-container guidance](https://developer.apple.com/forums/thread/125512).

| Artifact | SHA-256 |
| --- | --- |
| Submitted, before stapling | `85f9d92a0b20ea84db7f0c922d64ccd3bc7b26312d1d0fade3b7f5b154b5e875` |
| Final stapled DMG | `4974535a9c121a5d4040be4ef155f5c6bd0561ecfb2c6f52598675eaa00095d3` |

Final local artifact:

```
.build/direct-download/Tidy-Unqualified-b422b36-arm64-notarized.dmg
```

Apple receipt/log and safe local verification records are retained under
`.build/notarization/notary-b422b36-0uwkv_yg/`. No passwords or private key material
were exported. The profile authenticates with Keychain through Apple's tool.

Verified after stapling:

- `xcrun stapler staple` and `stapler validate`: pass.
- DMG signature and `hdiutil verify`: pass.
- Image metadata confirms UDZO, compressed and unencrypted; the regression test
  now checks these actual image properties rather than trusting its manifest.
- DMG Gatekeeper `spctl --assess --type open --context context:primary-signature`:
  accepted, `source=Notarized Developer ID`.
- Mounted read-only app's deep/strict signature: pass; its execute assessment is
  also accepted with `source=Notarized Developer ID`.
- Applications link and original app binary/Info.plist/CodeResources bytes: match.
- Verification volume detached; original submitted DMG/ZIP preserved.

No app was installed/launched during these CLI checks. They do not establish a
fresh Finder/quarantined download on a clean user or offline first launch. They
also do not revoke the owner's prior decision to defer formal native reruns.

Public promotion remains fail-closed. Owner approval of final branding, licensing,
hosting and support/privacy URLs, plus accurate compatibility/qualification claims
and final installer review, remain separate release decisions. No CI was used.
