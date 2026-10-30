# #15 recovery safety follow-up

2026-10-29. Focused recovery investigation, starting at `b5d3703` in
`/Users/chris/dev/utils/tidy-ticket-15`. Integrated `7f3fee4`, then `cf67c2e`
before final verification. Changes are limited to journal descriptor ownership,
coordinator-seam recovery regressions and this evidence. Release scripts,
packaging, model inputs and previous qualification evidence were not edited.

**Two product lock-lifetime defects were reproduced and fixed.** This is not a
claim that later passing runs erase the historical failure, or release approval.
#15 remains open; supported hardware remains **NONE qualified**. The unchanged
[corrective qualification results](qualification-v1-corrective-results.md) retain
their original scope and outstanding gates. No model corpus was rerun or retuned.

## Failure identity and limits

The historical unexpected `.busy` was reported in
`newerTaskConflictDoesNotPreventOtherSafeFilesInPartialTaskUndo`. Its original
managed log is no longer available, and the captured failure did not identify
the API phase or `flock` errno. Its exact original call cannot be reconstructed.
The original scenario now labels each phase and reports a safe error code/type.

The original test passed 100 isolated repetitions and the baseline full suite
passed 10 repetitions. These passes did **not** establish resolution. A new
contention test exposed descriptor corruption; after fixing that, a full-suite
run exposed a second unexpected `.busy` on repetition 7, specifically in an
independent fixture's sequential `undoHistory()` reader. That failed intermediate
run remains part of the evidence.

## Cause 1: rejected initialization closed a descriptor twice

`OperationJournal.init` assigned its stored descriptor before trying `flock`.
On rejection it manually closed the descriptor and threw. Swift runs `deinit`
after a fully initialized class initializer throws, so `deinit` closed it again.
Another thread could reuse that descriptor number between closes. This is
process-wide descriptor corruption, not shared fixture paths.

The public-coordinator regression
`rejectedCompetingHistoryReadsDoNotDisturbIndependentRecovery` holds a task's
journal in its progress callback, repeatedly requests history from a competing
coordinator, and concurrently exercises independent UUID-backed recovery fixtures
and history readers. It drains/cancels the rejector, releases and awaits the held
execution, then undoes retained operations and checks original bytes.

- With production journal code restored exactly to the baseline (verified by
  `git diff --exit-code`), the minimized regression failed **5/5 repetitions**.
  Failures included `.oneFileRequired`, `.uncertainIdentity`, and a failed
  external reposition, not just `.busy`.
- A temporary descriptor identity probe observed an acquired journal descriptor
  already closed: `errno=9` (`EBADF`). A separate Swift initializer probe
  confirmed `deinit` after a fully initialized throwing initializer.
- Fix: keep the opened descriptor local until exclusive acquisition succeeds.
  Rejection closes it once; only successful acquisition transfers ownership to
  the stored property and its destructor.
- Without the second fix, the regression passed 20 repetitions and the original
  plus contention tests passed 100 repetitions each. The subsequent full suite
  still failed on repetition 7: `Independent reopened-history read failed with
  code: .busy`. Core run: 104 tests, failed after 134.486 s. This ruled out
  declaring the initializer fix sufficient.

## Cause 2: close alone did not reliably release a lock during process launch

`historyRemainsAvailableDuringIndependentProcessLaunches` uses one coordinator's
sequential history reads while unrelated Foundation `Process` instances launch
`/usr/bin/true`. No second coordinator accesses that fixture during the reads.
Each process is awaited/reaped; the fixture is undone through a reopened
coordinator and original bytes are checked after successful contention.

- With the first fix but close-only destruction, the initial reproducer failed
  **5/5 repetitions**. Temporary instrumentation captured `flock` errno **35**
  (`EWOULDBLOCK`), not `EBADF` or an invented busy classification.
- Explicit `LOCK_UN` before close passed 10 repetitions of that larger
  reproducer (50,000 reads, four launchers with 250 processes each).
- Minimized to 2,000 reads and four launchers with 50 processes each, removing
  only the explicit unlock reproduced `.busy` **10/10 repetitions**. Restoring
  unlock is the final implementation. No failed read is retried or accepted.

Darwin `flock(2)` specifies that duplicated/fork-inherited descriptors share the
lock, and implicit release waits for the last reference to close; explicit
`LOCK_UN` releases it. `O_CLOEXEC` does not by itself close launch-time references
before exec. The process-launch reproduction and unlock-only red/green change
support this lock-lifetime mechanism. The exact transient holder inside
Foundation's launch implementation was not sampled, so its internal descriptor
duplication/inheritance path is an inference, not an observed child PID.

Fix: explicitly release the successfully owned lock in `deinit`, then close its
descriptor. Nonblocking exclusive acquisition, busy checks and critical-section
lifetimes are unchanged. No global serialization, sleeps, retries, dependencies
or weakened failure assertions were introduced. Temporary probes were removed.

## Release-path audit

- All journal construction sites use local RAII ownership: one-file sort,
  planning/metadata expansion, execution, history load/snapshot/clear, recovery
  reconciliation and file/task undo. Synchronous return/throw paths unwind the
  successfully initialized journal; it is not stored in coordinator state.
- Batch execution retains the journal across progress suspension and through
  the final callback (`withExtendedLifetime`). Its defer clears `activeTask` on
  exit. Cancellation breaks with completed changes retained; failure and thrown
  checkpoint paths retain durable recovery records and unwind ownership.
- Task/file undo checks cancellation before mutation; task undo checks each
  operation. Conflicts can preserve safe reversals and then throw. The local
  journal unwinds on either path, including persistence/checkpoint errors.
- Scoped directory/file descriptors and recursive directory duplicates have
  separate ownership and deferred closes. The rejected-initializer double-close
  could invalidate these unrelated descriptors before the fix.
- Native inspection's DEBUG SwiftPM path launches workers directly; packaged
  applications use the independent XPC broker. `WorkerSupervisor` closes its
  pipes and kills/reaps failed, cancelled and deadline-exceeded workers. The
  second regression exercises process launch in the same process as the journal,
  without relying on a parser failure or leaking workers.
- Existing cancellation/busy, interrupted-checkpoint, partial-undo, history and
  concurrent-submission tests remained enabled in full-suite repetitions.

## Final checks

On merged integration `cf67c2e`, with both fixes:

```sh
swift test --disable-automatic-resolution \
  --filter 'newerTaskConflictDoesNotPreventOtherSafeFilesInPartialTaskUndo|rejectedCompetingHistoryReadsDoNotDisturbIndependentRecovery|historyRemainsAvailableDuringIndependentProcessLaunches' \
  --maximum-repetitions 100 --repeat-until fail
swift test --disable-automatic-resolution --maximum-repetitions 10 --repeat-until fail
bash scripts/lint.sh
git diff --check
```

Runs used `caffeinate -i`, the normal parallel Swift Testing scheduler, and no
external network or dependency resolution. This is repeated debug-suite safety
testing, not model benchmarking.

| Final check | Result |
| --- | --- |
| Original recovery scenario, 100 repetitions | PASS, 23.342 s |
| Rejected-lock/independent recovery, 100 repetitions | PASS, 145.804 s |
| Process-launch/history regression, 100 repetitions | PASS, 100.788 s |
| Full suite, 10 repetitions per test | PASS: core 108 tests/13 suites, 135.436 s; model 12 tests/2 suites, 13.707 s; inspection 2 tests, 3.647 s |
| Strict Swift formatting, plist and shell lint | PASS |
| Diff whitespace check | PASS |

Both fixes also passed 100 focused repetitions and 10 full-suite repetitions on
the preceding integrated tip `7f3fee4` (core 105 tests, 134.953 s). Repetition
counts are per test, not ten separate fresh processes. No unexpected busy result
was suppressed. Raw final logs are local temporary artifacts
`tidy-busy-final-focused.8Cm8rD` and `tidy-busy-final-full.RozUhb` under the approved
OpenCode temporary directory; the outcomes above are the durable evidence.

## Remaining gap

The two reproducible mechanisms are addressed, but neither can be uniquely
assigned to the original uninstrumented historical `.busy`. These repeated
passes do not prove absence of all scheduling races. This follow-up did not
repeat optimized/signed hosted qualification, minimum-OS/hardware testing,
provider/GUI checks, pressure tests or independent human corpus scoring.
Existing release/qualification gates remain open. Mutation/undo-loop refactors
owned by the review fixer are outside this change set and require their own
verification after integration.
