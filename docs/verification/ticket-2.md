# Ticket #2: native folder inventory

## Local evidence — 2026-10-28

Environment: Apple M4 Max, 36 GiB memory, macOS 27.0.1 (26A434), Xcode 27.1
(27A9275), Apple Swift 6.4. No model/runtime is present in this read-only slice.
No remote CI was set up or used.

| Check | Result |
| --- | --- |
| `swift test` | Six real-directory coordinator tests passed; one real-provider test explicitly skipped because no fixture paths were supplied. |
| `bash scripts/lint.sh` | Passed strict Swift formatting lint, packaging plist validation, and shell syntax checks. |
| `bash scripts/build-app.sh` | Built and ad-hoc signed the sandboxed development app; strict code-signature verification passed. |
| `file .build/Tidy.app/Contents/MacOS/Tidy` | Mach-O arm64 executable. |
| `xcrun vtool -show-build .build/Tidy.app/Contents/MacOS/Tidy` | Minimum macOS version 14.0. |
| `codesign --display --entitlements - .build/Tidy.app` | Sandbox, user-selected read-only files, app-scoped bookmarks; no network entitlement. |

Red→green evidence from local runs:

1. Direct-child inventory initially returned no items; the real-directory test
   failed, then passed after enumeration was implemented.
2. Eligibility test initially failed on metadata and skip reasons; it passed
   after metadata-only filtering was implemented. Coverage also includes native
   Finder aliases, BSD hidden flags, hard/symbolic/broken links, and a FIFO.
3. Bookmark restoration initially returned no saved inventory; the test failed,
   then passed using actual scoped bookmark creation, persistence, resolution,
   and a new coordinator instance.
4. Cancelled empty-folder inventory initially succeeded and saved a grant; the
   test failed, then passed with cancellation checks before access/persistence.

Additional passing coverage rejects files/linked roots without saving a grant
and handles deleted folders/corrupt bookmark data without falling back. Tests
confirm original fixture bytes and nested-folder contents remain unchanged.
No file-content extraction or cloud/model transfer API exists in production
code. Only the app-owned bookmark data is read/written as contents.

## Still required: actual native UI and sandbox grants

Computer-use tools were unavailable in the implementation session. The app was
built and its package inspected, but **not launched or UI-tested**. The bookmark
test runs outside the app sandbox and reopens the coordinator within the same
test process; it is not proof of native panel authorization across app launches.
Do not mark these gates complete from the automated results above.

Run on a disposable fixture folder and the same signed app build:

- [ ] Open `.build/Tidy.app`; confirm a native window and folder selection panel.
      Cancel the panel and confirm no new grant/inventory is created.
- [ ] Select a fixture folder containing an ordinary unknown-extension file,
      a nested folder with a file, hidden file, app bundle, Finder alias, symlink,
      and `.download`/`.crdownload` items. Check names, counts, skip reasons and
      metadata. Confirm no nested child appears and original bytes/paths remain.
- [ ] Quit and relaunch without rebuilding. Verify the same folder is restored
      without another picker and no access outside the selected folder is used.
- [ ] Make the disposable folder unavailable (e.g. remove it after quitting),
      relaunch, and verify the reselection explanation with no stale inventory
      or fallback. Separately test actual permission denial/revocation on a
      supported OS; removal is not proof of real revocation handling.
- [ ] Select another folder and confirm only that folder is inventoried and
      remembered. Try an existing package/link as a root and verify rejection.
- [ ] Use a large disposable folder, check the window remains responsive, and
      cancel inventory. Verify the cancelled selection does not replace the
      remembered grant. Individual metadata calls can delay cancellation;
      responsiveness on slow/provider volumes remains a qualification gate.
- [ ] Repeat on macOS 14 (the minimum supported target). Current evidence is
      compilation for 14, not runtime qualification on 14.

## Still required: real provider eligibility without hydration

No cloud account, placeholder, or downloaded synced-file fixture was supplied.
The optional `NativePlaceholderTests` test is explicitly skipped in the normal
suite. An ordinary file with an `.icloud` suffix, synthetic flags, or a model
stub is **not** a substitute for a provider fixture.

- [ ] Prepare two disposable direct children in one provider folder: an evicted
      cloud-only file and an already-downloaded ordinary file. Establish native
      dataless/not-downloaded status without opening contents.
- [ ] Run the opt-in command in `README.md` and retain the result, provider name,
      OS version and hardware. It must report cloud-only skip, downloaded-file
      eligibility, and unchanged placeholder state after inventory.
- [ ] Repeat through the sandboxed app after native folder selection and after
      relaunch. Confirm the provider does not start downloading during inventory
      or refresh. Record provider-specific observations; the short metadata test
      alone is not a universal network/non-hydration proof.

These are unresolved acceptance gates, not claims of completed verification.
Developer ID signing/notarization and release hardware qualification are also
not provided by this development bundle.
