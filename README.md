# Tidy

A native Mac file organizer in development. Describe a rename/sort task in a chosen
folder; local inference prepares a validated plan. Clear requests execute without
preview, ambiguous requests need clarification, and changes to more than 100 files
require confirmation. Persistent undo is best-effort, not a backup.

**PUBLIC RELEASE BLOCKED. Supported hardware: NONE qualified.** Corrected synthetic
agent-scored quality/performance passes are not independent human, hardware or
safety qualification. See [qualification evidence](docs/verification/ticket-15.md).

## Workspace

Organize puts files first, with a task composer below the inventory and native
toolbar actions above it. History is the second sidebar destination. Model setup
and storage live in Settings (Command-comma); private diagnostics remain under Help.
Switching destinations does not cancel work. Downloads continue when Settings closes;
use the explicit Pause/Cancel controls. Closing the workspace requests cancellation
of file work and keeps completed changes available for best-effort undo.

The owner-approved Workspace A redesign is tracked in #17. See its
[implementation and review record](docs/verification/workspace-design.md) for the
checks run and the visual/accessibility work still requiring operator review.

## Local development

Use Apple silicon with Xcode 27.1 / Swift 6.4 including `swift format`. The build
targets macOS 14+, but macOS 14 and 16-GB Macs are not qualified. No CI is used.

```sh
bash scripts/build-app.sh
open .build/Tidy.app
swift test --disable-automatic-resolution
bash scripts/release-tests.sh
bash scripts/lint.sh
```

The debug script creates an ad-hoc-signed arm64 sandboxed app, **not a release**.
It has user-selected read/write access, app-scoped bookmarks and network-client
access for consented model setup. Do not use `swift run Tidy` as sandbox evidence.
Changing ad-hoc signatures can invalidate grants. Native parsing runs in a separate
contained XPC/parser boundary; packaged Metal resources and notices must be retained.

Tasks process names, contents and instructions locally, without telemetry/accounts/
cloud inference. Model setup explicitly downloads ~2.28 GB from Hugging Face;
subsequent tasks work offline with a verified installed model. Existing sync
services may transmit changes inside already-synced folders. Detected cloud-only
files are skipped, not hydrated; real-provider nonhydration qualification is open.

## Installation and distribution

- [Installation, model storage, privacy, history and undo](docs/install.md)
- [Blocked release prerequisites, naming investigation and operator commands](docs/distribution.md)
- [Local #16 build/signing/verification record](docs/verification/ticket-16.md)
- [Signed, notarized and stapled direct-download DMG evidence](docs/verification/dmg-distribution.md)

Local optimized Developer ID candidate packaging is explicit and unqualified:

```sh
bash scripts/package-candidate.sh --unqualified
bash scripts/package-dmg.sh --unqualified /path/to/signed-candidate.zip
```

Building the app candidate requires clean committed source and authorized signing
access; DMG packaging reuses an already signed candidate. These scripts never
upload, notarize or publish. The owner-authorized candidate DMG notarization is
recorded separately. Public promotion remains fail-closed pending owner review of
the final artifact, accurate qualification claims and remaining distribution gates.
This release targets DMG downloads through GitHub; any App Store release is later work.

## Verification boundaries

`TidyCore.TaskCoordinator(bookmarkFile:)` is the application test seam; tests use
real temporary files and bookmarks. Model lifecycle/runtime and packaged inspection
smokes supplement it. They do not establish native GUI behavior, real permission
revocation, app-process relaunch, hardware support or a clean-user installation.
See the [verification records](docs/verification/) for evidence and limitations.

`scripts/release-tests.sh` runs the same complete optimized coordinator suite in a
signed application test host with production XPC/parser containment, then the full
optimized model/supervisor suites and workspace state/native lifecycle checks.
Test-only app imports require `-enable-testing` in that script's test-build stage;
the staged production service/parser are built first without it. Unbundled
`swift test -c release` is not a substitute: internal app imports need testability,
and native inspection cases need the packaged parser service. Those failures are
not relabeled a pass. Hosted serial
coverage and the failed parallel stress attempt are recorded separately.

The workspace suites can also run without a model download:

```sh
swift test --disable-automatic-resolution --filter 'WorkspaceModelTests|SettingsLifecycleTests|WorkspaceGeometryTests'
```

They use temporary file fixtures and injected local completions. Native geometry
checks cover default/minimum windows in light/dark appearances, not full VoiceOver,
system-accessibility, live Liquid Glass, or older-macOS qualification.

Real-provider tests skip unless separately authorized disposable fixture paths
are supplied. Do not test personal sync data or read/evict placeholders to manufacture
nonhydration evidence. No provider fixtures are authorized for this work.
