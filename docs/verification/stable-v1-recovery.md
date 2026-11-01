# #15 — abrupt-process recovery qualification

Follow-up to the published experimental beta, 2026-10-31. Base source:
`598e4c5` on `ticket/15-stable-qualification`. Production behavior, model,
corpus, scoring denominators and thresholds are unchanged. No new dependency,
model download, CI, cloud fallback or personal/provider fixture is involved.

## Executable coverage

`ProcessRecoveryTests.killedProcessReconcilesWithoutResuming` exercises eight
durable operation checkpoints through the public coordinator. A separate
test-only executable sends itself SIGKILL at the chosen checkpoint, without
throwing, running Swift defers, releasing its journal lock or finalizing a task.
The parent requires termination by SIGKILL and a reaped child, not merely an
unsuccessful exit. A 20-second child alarm makes a stalled fixture fail.

Before reopening, the test decodes the actual persisted operation journal and
checks that only the first operation exists with its expected durable state.
It verifies source/destination bytes and preserves an unrelated hidden file.
Forward tasks contain a second eligible file, which must remain untouched.

| Kill checkpoint | Persisted state | Expected recovery |
| --- | --- | --- |
| Intent saved | intent | Unapplied; no destination folder |
| Folder created, identity not yet saved | intent | Uncertain; unidentified folder retained |
| Before move | intent | Unapplied; identified empty folder retained |
| After move, before completion saved | intent | Completed from observed identity |
| Completion saved | completed | Completed |
| Undo intent saved | undoIntent | Completed; undo is not silently resumed |
| After undo move, before completion saved | undoIntent | Undone from observed identity |
| Undo completion saved, before folder cleanup | undone | Undone; folder retained |

A fresh invocation of the **same executable** restores its bookmark and emits
recovery statuses without selecting or regranting the folder. The parent then
regrants only its own disposable fixture access: it is a different executable
identity. Parent-side repeated recovery must leave journal bytes unchanged and
must not move any file or remove folders. Explicit undo checks lock availability,
preserves later edits, and removes only an identified empty task-created folder.
Explicit cleanup preserves a file added later to that folder; it removes the
folder only after that file has been separately removed by the test.

The helper is a test target, not bundled into the production app. The hosted
optimized suite selects its matching optimized helper with
`TIDY_RECOVERY_TEST_WORKER`. Debug tests find their sibling build product.

## Verification

Test machine: Apple M4 Max, 36 GB, MacBook Pro `Mac16,6`, macOS 27.0.1
(`26A434`). This is an observed configuration, **not qualified supported hardware**.

- Focused debug run: PASS, all eight SIGKILL cases, including fresh-process
  bookmark restoration and recovery.
- Repeated final focused run: PASS, 25 repetitions / 200 SIGKILL-and-restart
  scenarios. The direct debug SwiftPM helper was given Xcode's test framework
  and library search paths; no production signing or library-validation change.
- Complete debug suite: PASS, 124 coordinator, 13 model, two worker and 18
  workspace functions reported. One real-provider test skipped, not executed.
- Complete hosted optimized suite: PASS, matching all 124 discovered coordinator
  functions, plus the complete model, worker and workspace suites. Same provider
  skip. Final repeat after strengthening the cleanup assertion also PASS:
  all 124 hosted coordinator functions, 13 model, two worker and 18 workspace
  functions reported; same explicit provider skip.
- Strict Swift format, plist and shell syntax lint: PASS.
- ShellCheck of the changed release-test script: PASS.
- Diff whitespace check: PASS.

Commands:

```sh
swift test --disable-automatic-resolution --filter ProcessRecoveryTests
swift test --disable-automatic-resolution
bash scripts/release-tests.sh
bash scripts/lint.sh
git diff --check
```

Initial harness failures are not product failures or hidden passes: the first
helper called `_exit(3)` immediately after sending SIGKILL, racing signal delivery.
It now waits for actual signal termination. The next parent-only recovery attempt
could not use the other executable's security-scoped bookmark. The final test
checks restoration in a new same-helper process, then explicitly regrants the
different parent identity. All eight final focused cases pass.
An initial direct-helper repetition attempt failed before loading tests because
XCTest's framework path was absent; the configured 25-run attempt passed.
One final optimized-repeat invocation exceeded the shell's 120-second timeout
during rebuilding, before tests ran; it was restarted as a background command.
That restarted command completed successfully with the full results above.

## Remaining #15 gates

Subsequent [remaining-host checks](stable-v1-remaining.md) add case-sensitive APFS,
detached-volume recovery, isolated native destructive controls, model replacement
fixture SIGKILL, real URLSession partial cleanup/eviction, storage rejection and
native scope/recursive undo evidence. The table below records this document's
earlier disposition; use that follow-up for current per-check limits.

This closes the automated **actual process interruption at the exposed durable
checkpoints** gap, not the whole recovery/hardware qualification requirement.
It does not simulate power loss, kill between arbitrary filesystem instructions,
qualify other volumes, exercise a native app restart, establish native picker
permission restoration or prove every hostile timing safe.

| Gate | Remaining evidence |
| --- | --- |
| Native folder authority | [Installed-beta checks](stable-v1-native-permissions.md) now cover selection, restoration, cancellation, POSIX denial and original-folder regrant; sandbox/TCC revocation and remaining stale/unavailable/reselected-folder cases stay open |
| Provider behavior | Separately authorized disposable cloud-only/downloaded fixtures and observed nonhydration across traversal/refresh/relaunch |
| Recovery breadth | Supported-volume/case-sensitive execution and remaining external replacement/stress cases |
| Native task acceptance | Remaining final-workspace boundary/scope/inspection/result checks, carrying forward actual earlier passes |
| Model lifecycle | Isolated-profile destructive controls, transfer/replacement termination, resume-temp eviction, storage shortage and pressure |
| Naming quality | Independent assessment and broader representative scripts, scans and codecs; existing agent-scored corpus results remain supplementary |
| Supported configurations | Actual minimum OS/hardware and sustained/pressure/resource evidence; none qualified |
| Privacy/error behavior | Remaining final-app native diagnostic/error observations and retention/transmission evidence |

Existing owner deferrals of formal undo-cancellation, native-offline and diagnostic
wizard reruns are unchanged. Accessibility remains #18; distribution remains #16.
No check is marked passed solely because another implementation ticket closed.
**Keep #15 open. Supported hardware: NONE qualified.**
