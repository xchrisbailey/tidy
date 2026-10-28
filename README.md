# Tidy

A native, local-only Mac file organizer in development. This first slice is a
**read-only folder inventory**, not a plan preview: it does not rename, move,
read document contents, or download files. No account, inference runtime,
analytics, crash-report uploader, or third-party dependency is included.

## Local development

Use an Apple silicon Mac with Xcode and a Swift 6 toolchain that includes
`swift format` (verified with Xcode 27.1). The app targets macOS 14 or later;
older supported OS versions still need qualification. No CI is configured.

```sh
bash scripts/build-app.sh
open .build/Tidy.app
swift test
bash scripts/lint.sh
```

The build script creates an arm64, ad-hoc-signed, sandboxed development app.
Its only external-file entitlement is **user-selected read-only access**,
with app-scoped bookmarks. It has no network entitlements. This is not a
Developer ID signed/notarized distribution build. Use the app bundle, not
`swift run Tidy`, to check sandbox behavior. Rebuilding an ad-hoc signature can
invalidate remembered permissions; use the same build for relaunch checks.

Choose a folder in the native folder picker. Tidy remembers one read-only
security-scoped grant in its sandbox's Application Support/Tidy directory and
restores it on launch. Unavailable/corrupt grants require selection again;
there is no fallback to a parent folder or another location. The app does not
persist the inventory or document excerpts.

The inventory lists direct children, candidate-file counts, and skipped items
with reasons. Existing folders are not traversed. Unknown ordinary file types
remain eligible for metadata inspection; eligibility does not promise support
for content-based naming. Hidden items, packages/app bundles, symbolic and hard
links, Finder aliases, special files, recognized incomplete-download names,
and detected cloud-only files are skipped. Downloaded ordinary files remain
eligible. Existing sync services may transmit changes from future organizing
tasks; Tidy itself does not initiate downloads.

## Application boundary

`TidyCore.TaskCoordinator(bookmarkFile:)` is the confirmed application testing
seam. Call `selectFolder(_:)` with the URL supplied by native selection, or
`restoreFolder()` to inspect the saved grant. Calls are actor-isolated,
cancellable, and return an immutable `FolderInventory` with metadata and
per-item skip reasons. Native UI holds no filesystem traversal logic. Tests use
real temporary directories and real bookmark APIs, not a mock filesystem.

The injected bookmark location is app-owned storage, **outside the selected
folder**. Bookmark restoration disables UI and volume mounting, balances scoped
access, and renews stale grants only after successful inventory. Inventory IDs
are filenames unique to this direct-child snapshot, not persistent file identity.
Neither the returned URL nor its metadata is future authorization to mutate:
later task slices must reacquire a grant, implement recursive intent explicitly,
enforce task limits, and recheck identity/state before operations. This slice has
no request interpretation, inference, plan, execution, history, or undo API.
Future mutation support must deliberately upgrade the read-only grant and
sandbox entitlement; it must not silently assume this grant permits writes.

## Native acceptance checks

See [the native checklist and recorded evidence](docs/verification/ticket-2.md).
`swift test` alone does **not** verify native folder-picker permission grants,
sandboxed relaunch, real revocation, or cloud-provider non-hydration.

The provider test is deliberately skipped unless real fixture paths are supplied.
Use a disposable provider folder with an ordinary downloaded file and a real
evicted placeholder (not a renamed local file), both direct children:

```sh
TIDY_PLACEHOLDER_PATH='/absolute/provider/folder/placeholder.pdf' \
TIDY_DOWNLOADED_PATH='/absolute/provider/folder/downloaded.txt' \
swift test --filter NativePlaceholderTests
```

Do not print/open the placeholder's contents while preparing the test. The test
checks native dataless/iCloud metadata before and after coordinator inventory,
including a short delayed check, and confirms the downloaded file is eligible.
It neither creates nor evicts cloud files. Use the sandboxed app checklist as
well; a command-line test is not evidence of native user-granted sandbox access.
