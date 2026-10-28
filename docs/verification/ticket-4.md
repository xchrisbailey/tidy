# Ticket #4: safe batches

## Scope and integration

Started with a clean `ticket/4-safe-batches` at the agreed `eb7e84b` base.
Merged `integration/tidy-v1` including #13 (`b5d4868`) and adapted its existing
history snapshot/window rather than introducing another history store. Then merged
the advanced tip `0ecf6a9` including #6's model setup/dependencies. Work is
provisional: earlier native acceptance gaps remain open. No ticket was closed.

## Application boundary

- `planSortByType(request:)` accepts the explicit deterministic request. It builds
  the entire immutable plan before mutations, rejects more than 1,000 eligible
  direct children, validates destinations and component lengths, and reserves
  existing and planned names. Original proposed names have priority over suffix
  allocations: with existing `notes.txt` and incoming `notes.txt`/`notes (2).txt`,
  the former becomes `notes (3).txt` and the latter keeps its name. Suffixes start
  at 2; extensions and bytes are preserved. Case variants are conservatively
  reserved too. Unknown types are skipped, never inferred as duplicates.
- `execute(_:confirmed:progress:)` requires explicit confirmation above 100 distinct
  changed files. `changedCount`, `renameCount`, and `moveCount` are separate:
  renaming and moving one file counts once toward confirmation. The main UI shows
  the counts in a confirmation alert, not a general preview for smaller tasks.
- Execution revalidates the whole destination plan before any mutation and
  rechecks each source snapshot immediately before its operation. Progress is an
  async callback with task ID, processed/total and actual changed counts. Cancel
  the calling Swift task to stop between operations. Completed moves remain;
  stale/missing sources are skipped and explained, not replaced or overwritten.
- `BatchResult` separates changed, unchanged, skipped, failed and unprocessed
  files, cancellation and task-level failure explanations. `OutcomeReason`
  distinguishes future abstention from already-organized outcomes; this explicit
  direct-child type sort itself has no rename-only or model-abstention behavior.
  Empty/zero-change outcomes are explained. A move followed by a flush/final-save
  failure is checked for actual identity and reported as changed with uncertain
  recovery completion, not falsely reported as untouched.
- The existing directory-relative, no-follow, exclusive rename and durable journal
  protocol remains in use. A journal lock spans execution, including progress
  callback suspension. Concurrent tasks, undo, snapshot/clear and grant changes
  cannot mutate the active task's journal. Do not await another mutation from a
  progress callback expecting it to queue: overlapping submissions return `busy`.
- `FileOperation.id` identifies one operation; `taskID` groups a batch and
  `destinationName` records suffix renames. Old journals fall back to the operation
  ID/original name. `undoTask(taskID)` holds one lock across best-effort group undo;
  conflicts do not prevent other safe files being restored. Journal/filesystem
  failures stop undo. `undoFile(id)` remains individual. Shared task-created
  folders are removed only when safely identified and empty.
- #13's observational `historySnapshot()` now exposes ordered `tasks`, and its
  history window groups files by those IDs and routes task/file undo separately.
  `resultingPath` includes suffixes. Existing measured record storage, explicit
  undo-loss confirmation and atomic storage clearing are preserved.
- The old one-file `sortByType(request:)` remains for compatibility with its
  original safety tests; the main task UI uses the batch APIs.

## Local evidence — 2026-10-28

Tests use the agreed public `TaskCoordinator` seam, real temporary files and
bookmarks, and reopened coordinators for persistent undo. No internal mocks or
test-only filesystem fault hooks were added.

Observed red → green slices:

1. Collision reservation/reopened batch undo failed compilation without the
   batch APIs; it passed after implementation.
2. A late occupied destination initially left a misleading intent that caused
   task undo to throw uncertain identity. Rechecking occupancy before recording
   intent preserved the external file and allowed completed batch undo.
3. An overlong suffixed destination initially passed planning. Component-length
   validation now rejects the entire plan before creating an earlier destination.
4. After merging #13, batch history assertions failed without grouped task
   snapshots. Grouping and collision-aware resulting paths now pass.
5. Cancellation-time history clear initially returned cancellation instead of
   `busy`; explicit active-task guards now preserve the mutual-exclusion contract.

Supplemental passing coverage checks 100/101 distinct changes with an overlapping
rename+move, confirmed execution of 101 files, accepted 1,000-file planning and
execution cancelled after one move, rejected 1,001-file planning, hidden-item
exclusion, validation both before and after planning, late source edits/deletion,
continued execution past skips, cancellation with retained history, conflicting
destinations, real journal write denial, individual and best-effort group undo,
and preservation of original conflicts/unrelated destination files. Existing
inventory, one-file safety/reconciliation and history-clear tests remain intact.

| Check | Result |
| --- | --- |
| Baseline `swift test` at `eb7e84b` | 18 executed tests passed; one provider fixture test skipped. |
| `swift test` after #13, before final #6 merge | 30 executed tests passed; one provider fixture test skipped (31 reported total). |
| `bash scripts/lint.sh` | Passed strict Swift formatting, packaging plists and shell syntax, including after the final #6 merge. |
| `git diff --check` | Passed, including after the final #6 merge. |
| `bash scripts/build-app.sh` before #6 merge | Built sandboxed arm64 development app, ad-hoc signed and signature verified. |
| `codesign --display --entitlements - .build/Tidy.app` before #6 merge | Sandbox, scoped bookmarks and user-selected read-write; no network entitlement in that build. #6 adds its setup network entitlement in the merged source. |
| Integrated test/build after #6 merge | Test attempt blocked by uncached MLX submodules with network denied; final integrated app build not repeated past that dependency blocker. |

No dependencies were introduced by #4; #6's existing approved dependency graph
was preserved when merging. No CI, successful external network access, model
download or primary-worktree document edits were performed by this worker.

### Exact integrated-check blockers

Both commands ran in `/Users/chris/dev/utils/tidy-ticket-4`:

1. `sandbox-exec -p '(version 1) (allow default) (deny network*)' swift test --skip-update --disable-automatic-resolution`
   failed before tests: SwiftPM's nested manifest sandbox reported
   `sandbox_apply: Operation not permitted`.
2. `sandbox-exec -p '(version 1) (allow default) (deny network*)' swift test --disable-sandbox --disable-automatic-resolution`
   retained the outer network denial and disabled only SwiftPM's nested sandbox.
   Root packages were copied from local caches, but the MLX `mlx` and `mlx-c`
   submodules were not cached in this worktree. SwiftPM's submodule clone attempts
   failed with `Could not resolve host: github.com` under the network denial.

No network permission was requested or enabled, and no command is awaiting
approval. These are explicit failed integrated checks, not passing test evidence.

## Open manual gates

Native GUI tools are unavailable. The bundle was built/inspected but not launched
or interacted with. Coordinator reopen tests run outside the sandbox, within the
test process; they are not evidence of native consent or an actual app restart.

- [ ] In the signed app, grant a disposable folder; run 100 files (including a
      collision rename) without confirmation, then 101 with exact counts. Cancel
      the large-task alert and verify no moves; confirm and inspect results.
- [ ] Check 1,000 eligible files, narrow-scope rejection at 1,001, unknown types,
      existing sorting folders and case-sensitive filesystem collision behavior.
      Full 1,000-file execution throughput was not measured in the automated test.
- [ ] Cancel during native execution; verify responsiveness, progress, all per-file
      reasons, unprocessed files and no automatic rollback. Exercise concurrent
      task/undo/clear from both windows and native keyboard/VoiceOver behavior.
- [ ] Quit/relaunch the same signed build; verify grouped history, actual suffixed
      paths, task and individual undo, original-location conflicts, clear-history
      cancellation/confirmation and storage bytes without touching user/model data.
- [ ] Qualify actual sandbox write denial/revocation, picker cancellation, stale
      grants, real provider placeholders, macOS 14 and supported filesystems.
- [ ] Qualify actual process interruption/power loss and hostile external directory
      replacement timings. Existing recovery fixtures are not crash experiments;
      the post-rename flush/final-save failure-reporting path was inspected but not
      forced with a real filesystem fault in this session.

These remain acceptance gaps, not completed checks; #2, #3, #4 and #13 are not
claimed closed by this evidence.
