# #15 — resumed native matrix

**Later fix:** [Clarification follow-up](stable-v1-clarification.md) reproduces and
fixes the three plan-error cases below and observes native questions/resubmission/
undo. This matrix's initial failed attempts remain historical evidence.

2026-11-02. The owner reported the Mac available again. Accessibility access to
the isolated **Tidy Matrix Test** app now worked. This supplements, not replaces,
the [overnight blocked attempt](stable-v1-overnight.md). **#15 remains open.**

## Isolation and method

Used the prepared, deep-strict-signature-verified bundle from the current local
worktree, including the PNG/JPEG framing fix, based on `dc5ea7ee`. Its executable,
parser and prepared source hashes matched `.build/native-matrix/profile.json`.
Only the unique `dev.xchrisbailey.tidy.matrixtest.…` container and owned synthetic
fixtures under `.build/native-matrix/Fixtures` were used. Approved weights were
APFS-cloned into that container with distinct file inodes; no download occurred.

Requests were physically typed, followed by Tab and a fresh Accessibility snapshot
verifying the exact request before submitting. Folder grants were verified against
the exact owned path and write-grant status before tasks. Action-success envelopes
alone were not counted as results: UI observations were checked against actual
fixture hashes, paths and the isolated operations journal.

## Native observations

| Check | Actual result |
| --- | --- |
| Large-task disclosure | `Sort by type` displayed **101 distinct files: 0 renames and 101 moves**. Before consent, all 102 fixture files, including the hidden control, were unchanged; no journal task or sorting folder existed. |
| Confirmation Cancel | Native Cancel showed **Task not started / Confirmation was cancelled. No files changed.** Exact paths/hashes and empty history verified. |
| Confirmation accept | A fresh identical confirmation was accepted: **101 changed, 0 failed, 1 skipped**. Exactly 101 completed operations in one batch; all moved bytes and hidden control unchanged. Details showed summary and before/after rows. |
| Actual relaunch and undo | Confirmed process `50476` exited; new process `50765` reached Ready. History showed exact `Confirmation101` path and **101 recorded changes · 0 undone**. Native Undo Task reported **101 of 101**. All original paths/hashes restored; empty task-created `Documents` removed. |
| Ambiguous requests | `Organize these files`, `Sort only notes.txt by type`, and `Rename these files` each showed **Couldn’t finish / The local model did not return a complete authorized plan after one replacement. No files changed.** No new records or mutations. **No clarification question was observed; native clarification remains unverified.** |
| Explicit resubmission | `Sort by type` after those errors completed **2 changed, 0 failed, 1 skipped**. Exact `Clarification` history task undone natively **2 of 2**; original names/bytes and hidden control restored; empty sorting folder removed. This is recovery after plan errors, not a successful clarification dialogue. |
| Unsupported deletion | `Delete all files` showed **That request isn’t supported**, entire request declined, no files changed. Fixture set/hashes and journal count unchanged. |
| Content disclosure | Native How Tidy Works popover described supported local evidence, inspection limits, cloud-only exclusion and sync-service caution. Recovery text was exposed but offscreen; do not claim every paragraph was visually reviewed. |
| Content naming | Both synthetic content attempts completed one rename with original bytes preserved. The body-only second probe produced **Acme Invoice AB123 2026-10-28.txt**. |
| Content relaunch and undo | After second-probe process `51335` exited, new `51408` reached Ready. Exact `ContentFixture` history showed one recorded change, zero undone; native Undo Task reported **1 of 1** and restored original name and second-probe bytes. |

## Content-canary boundary and failed first assertion

The first fixture's numeric/underscore canary became part of the filename:
`Acme Invoice AB123 2026-10-28 TIDY_BODY_RETENTION_CANARY_….txt`.
The expected canary-absence assertion **failed**. Naming protects numeric content
tokens (`Sources/TidyCore/ContentNaming.swift:97–100`); filename/recovery persistence
therefore cannot distinguish body retention in this attempt. Its marker remains
legitimately in the undone record's resulting filename. Do not report this attempt
as a retention pass or silently erase its history.

After native undo and confirmed exit, the original fixture bytes were retained
separately and a second, independently hashed probe substituted only an alphabetic
body marker. It was not included in the resulting filename. After naming, actual
relaunch, native undo and confirmed exit, that exact marker was absent from the
**eight accessible regular files** scanned inside this isolated container:
bookmarks, journal/lock, preferences, active-revision and the two unrelated canaries.

The scan was bounded to regular files at most 32 MiB; no symlinks were followed,
and the cloned model revision was excluded. Thirteen entries were skipped: twelve
symlinks and OS-protected container-manager metadata. An initial permission error
was retained; no permission bypass was attempted. This is exact-byte marker absence,
not compressed/encoded-store analysis, memory erasure, OS-wide log inspection,
telemetry/network attribution or a forensic no-retention guarantee. The explicit
original fixture was restored afterward and matched its original baseline hash.

## Automation failures preserved

- Grant picker/menu automation had transient Accessibility surface failures and
  premature Go To observations. Fresh snapshots established the actual modal
  state before continuing; no blind repeated modal-opening action was used.
- A 101-item picker tree truncated before its footer. Return completed that grant;
  exact selected main-window path/count/write authority were independently checked.
- Text waits matching the **Clarification window title** were not treated as an
  actual question. A `Needs clarification` wait timed out; fresh task-result
  snapshots showed plan errors. No ambiguity success was inferred from waits.
- A deletion wait for `not supported` timed out; the actual UI uses **isn’t
  supported**. A fresh snapshot and unchanged hashes established the refusal.
- The post-removal `Setup Required` wait timed out. A fresh Settings snapshot showed
  **No installed model** and the revision directory was independently absent.

## Cleanup and retained evidence

Native Settings **Remove… → Remove Model** removed only the isolated clone. Both
unrelated storage/user-data canaries remained exact. All 11 approved-source model
hashes and every original fixture path/hash were rechecked unchanged. All **105**
operation records were retained, all undone: 101 confirmation moves, two explicit
resubmission moves and two separate content renames. No history clearing or manual
substitute for app undo was used; only the explicitly recorded second-probe fixture
substitution/restoration was performed outside the app after it exited.

Final app process `51488` exited gracefully with process-exit confirmation. Only
this app's temporary LaunchServices registration was removed. The isolated bundle,
container/history and synthetic evidence remain retained; installed Tidy data and
source weights were untouched.

Local evidence: `.build/native-matrix/native-resume-results.json`, original profile/
baseline, verified submission and picker snapshots, content disclosure/history/
relaunch snapshots, deletion/ambiguity results, second-probe baseline and
`retention-scan.json`. The earlier blocked results remain historical evidence.

## Remaining gates

This closes the specific native confirmation/cancel, bounded relaunch/undo,
unsupported-deletion and body-only marker checks above. It **does not** qualify
native clarification, genuine TCC revocation, durable filesystem identity across
volume incarnations, independent naming review, minimum hardware/macOS, sustained
memory pressure or replacement between two reviewed production models. Existing
formal undo-cancellation, native-offline and diagnostic-export deferrals and #16/
#18 dispositions remain unchanged. Nothing committed, pushed, merged or released.
