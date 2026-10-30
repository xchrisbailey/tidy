# Direct distribution: blocked prerequisites and operator procedure

**PUBLIC RELEASE BLOCKED. No hardware qualified.** #16 supplies local candidate
packaging, not a public release. #15's corrected synthetic agent-scored quality
and 100-file passes are not independent human/hardware/safety qualification.
Keep both issues and parent #1 open. No upload/push/publish occurs in these scripts.

## Naming investigation (2026-10-29)

“Tidy” remains an internal working name, **availability unresolved**. A primary
vendor source already advertises [Tidy Up 6](https://www.hyperbolicsoftware.com/TidyUp.html),
a Mac duplicate finder/disk-tidiness product with direct ZIP downloads. That is a
related name/product area, not proof of infringement or permission. Do not treat
an available repository, bundle identifier, domain or App Store name as clearance.

The [USPTO search guidance](https://www.uspto.gov/trademarks/search) and
[comprehensive clearance guidance](https://www.uspto.gov/trademarks/search/comprehensive-clearance-search-similar-trademarks)
call for similar-mark, common-law and registry research; reading them is not a
clearance search. No exhaustive registry/common-law/international search, legal opinion,
domain/social reservation, or right to use this name has been obtained. Owner must
choose target jurisdictions, resolve confusingly similar names and get appropriate
legal review or select another name before public use. No registrations/accounts
or purchases were made. A rename must include bundle/storage/bookmark migration
review, not just the ZIP filename.

## Repeatable local candidate build

Use the committed pinned `Package.resolved`, Apple silicon, Xcode 27.1 / Swift 6.4
as recorded in qualification. No new dependencies, CI or remote verification.
The scripts build optimized **release** configuration, copy native XPC/parser,
Metal bundles and third-party notices, sign inside-out with hardened runtime and
secure timestamps, verify strictly, and make a native Finder-expandable ZIP.
They do not package model weights or silently rename `.build/Tidy.app` as a release.

From the clean committed worktree `/Users/chris/dev/utils/tidy-ticket-16`:

```sh
swift test --disable-automatic-resolution
bash scripts/release-tests.sh
bash scripts/lint.sh
git diff --check
bash scripts/package-candidate.sh --unqualified
# Pass the exact output directory printed above, not a guessed “latest” path:
bash scripts/candidate-smoke.sh /absolute/path/to/unqualified-output-directory
```

Also record `swift test --configuration release --disable-automatic-resolution`:
the current unbundled release test runner fails PDF/OCR tests with inspection
`unavailable`, because the SwiftPM supervisor adapter is intentionally DEBUG-only.
Production/release inspection requires the packaged XPC service. Do not add an
in-process parser or release CLI fallback to turn this into a pass. Its failed
history remains a failure. Use `bash scripts/release-tests.sh` for the full proper-host
optimized verification: all coordinator cases, not just the model smoke examples.

The harness copies Xcode's SwiftPM testing helper into a signed, hardened local
`.app`, loads the same optimized `TidyCoreTests.xctest`, and supplies the normally
linked production XPC service/parser with their unchanged containment profile.
Test-only Apple-framework linker paths avoid DYLD injection/library-validation
exceptions; production helper binaries are staged before that test-only link.
The copied/local Xcode runner is not included in the download artifact.
Source-vs-host discovery must match exactly and be nonempty; the run must report
all discovered functions passing. Real-provider coverage still skips without an
explicit authorized fixture. Complete optimized model/transfer/supervisor suites
then run in their normal CLI host, preserving their real loopback transfer tests.

This **test-only** host has the same unsandboxed fixture authority as the original
CLI runner: existing tests create bookmarks programmatically, not via native picker
grants. It does not certify the production app's App Sandbox permissions; those
entitlements are not changed. The independent production parser remains sandboxed,
with no in-process fallback. Hosted tests run serially to match the app's one-task
boundary; concurrency inside each test is unchanged. A parallel hosted attempt
hit unchanged inspection deadlines and remains failed stress evidence, not a pass.

`bash scripts/release-tests.sh --without-service` is a negative control: the same
five OCR parameter cases must fail with inspection `unavailable` (exit 1), proving
the proper-host pass depends on the production service. Missing/incorrect entry
points or incomplete discovery cannot count as a pass. Local hosts/discovery lists,
logs and source/toolchain/signature hashes remain under `.build/release-tests/`.
Neither hosted suites nor packaged model smokes replace native GUI/clean-user,
hardware, manual recovery or final signed/notarized distribution qualification.

Default authorized certificate SHA-1:
`DDB64DD6A0BB35AA612980AEDD27B781C6A1E6F0`, Developer ID Application:
CHRISTOPHER BRIAN BAILEY (`5U2B7W5F39`). `TIDY_SIGN_IDENTITY` can select another
explicitly authorized certificate hash; it is not a qualification override.
If codesign prompts, keychain access fails or approval is pending, stop and have
the lead/user run the same command from that workdir. Never bypass access controls,
read secrets, or repeatedly retry a pending request. Certificate presence alone
does not prove private-key access, account standing or notarization authorization.

Output lives under ignored `.build/direct-download/unqualified-<source>.XXXXXX/`:
ZIP, SHA256SUMS, bundle hashes, signature/entitlements records and BUILD.txt with
source/toolchain/lockfile provenance. Each run uses a fresh directory; old artifacts
are retained. Signing timestamps and archive metadata vary: **bit-for-bit
reproducibility is not claimed**. Compare pinned source/toolchain and inputs, retain
exact final hashes. Diagnostic smoke uses the optimized binary and candidate's
resources/signed helpers, but a separate non-App-Sandbox diagnostic identity; it
cannot establish actual GUI grants, setup consent or clean-user behavior.

`bash scripts/package-release.sh` **always exits 1 before building/signing/uploading**.
There is intentionally no `RELEASE_APPROVED=1` escape hatch. A future reviewed change
must consume actual qualification evidence, final-artifact hashes/checklist and
owner approvals before implementing promotion. Never relabel today's candidate.

## Notarization: user-owned step, not performed automatically

[Apple Developer ID guidance](https://developer.apple.com/developer-id/) requires
appropriate signing, hardened runtime and testing, and documents `notarytool` and
`stapler`. No notary credential/profile has been supplied or authorized here.
No keychain credential discovery, secret extraction or account setup is permitted.
No unqualified artifact is to be uploaded by this implementation.

**Only after owner authorization to submit a reviewed artifact**, an operator must
configure an authorized notarytool profile themselves (no secrets in git/chat).
These are exact command forms, not commands already executed; replace the profile
and paths with explicit authorized values. Run from the candidate output directory:

```sh
xcrun notarytool submit Tidy-Unqualified-Development-arm64.zip --keychain-profile AUTHORIZED_PROFILE --wait --output-format json > notary-result.json
# Require status Accepted, retain submission ID and review notary log on failure.
xcrun stapler staple 'Tidy-Unqualified-Development/Tidy Unqualified Development.app'
xcrun stapler validate 'Tidy-Unqualified-Development/Tidy Unqualified Development.app'
codesign --verify --deep --strict 'Tidy-Unqualified-Development/Tidy Unqualified Development.app'
spctl --assess --type execute --verbose=4 'Tidy-Unqualified-Development/Tidy Unqualified Development.app'
# Preserve the submitted ZIP/hash. Make a distinct archive of the stapled app:
ditto -c -k --sequesterRsrc --keepParent Tidy-Unqualified-Development Tidy-Unqualified-Development-arm64-stapled.zip
shasum -a 256 Tidy-Unqualified-Development-arm64-stapled.zip
```

Stapling changes the artifact: retain both hashes; test the exact extracted stapled
download with quarantine/Gatekeeper intact, online first launch and offline launch.
An Accepted ticket does not qualify the product or approve public distribution.
Final public naming/version packaging and final checks must be separately reviewed.

## Required release review: all unresolved unless recorded otherwise

- [ ] #15 independent quality review, representative scans/scripts, minimum-hardware
  and OS matrix, memory pressure/native parser peaks; no inferred 16-GB/macOS-14 pass.
- [ ] Diagnose/review the intermittent recovery `.busy`; establish repeatability
  and actual process/power-loss recovery. Keep historical failures visible.
- [ ] Real native read/write grants, restoration/revocation and separately authorized
  disposable-provider nonhydration. Never use personal sync data as test fixtures.
- [ ] Clean macOS user with no developer weights/bookmarks/history: install exact
  signed/notarized archive, normal Gatekeeper/first launch; no bypasses.
- [ ] Initial setup consent/download, interruptions/resume/cancel, storage bytes and
  removal/replacement; clear task, clarification/resubmission, >100 confirmation,
  progress/cancel/results and keyboard/VoiceOver. Preserve originals to compare bytes.
- [ ] Real app quit/relaunch, task/file undo and conflicts, history/clear consent;
  offline readiness and real task with networking disconnected after setup.
- [ ] Name/legal review, app licensing/distribution terms and dependency/model notice
  review (including conversion provenance limits) approved by owner. No project
  redistribution license is inferred merely from free/account-free product intent.
- [ ] Developer ID use/account standing; authorized notary profile, Accepted result,
  stapled/validated artifact, final hashes and clean-user Gatekeeper results.
- [ ] Owner-approved HTTPS hosting/download/support/privacy location and publishing
  access; availability and certificate/download integrity checks. None selected or
  provisioned. No cloud account, CI, telemetry, payment or App Store work is added.
- [ ] Final source + lockfile recorded; complete local release tests/lint/smokes and
  signed-artifact checks on integrated tip; human approves evidence and final release.

For each manual check record tester/date, Mac/RAM/OS, artifact SHA-256, exact steps,
observations and pass/fail. Blank checkboxes and environment flags are not evidence.
