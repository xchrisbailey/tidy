# Ticket #5: interrupted recovery and repeated-file undo

## Scope and integration

Started clean on `ticket/5-recovery` at the agreed `1f5a202` base. Implementation
commit `6eec27b` was merged with `integration/tidy-v1` through `23d4574`, including
#12 model storage, without conflicts. Work remains provisional while native
acceptance gaps remain open. No issue was closed; no dependencies, CI, cloud
inference, or user-facing documentation were added.

## Boundary and behavior

- `TaskCoordinator.undoHistory()` already runs in the main window's startup
  inspection flow. It now reconciles pending records newest-first, using actual
  single-link regular-file identities and pinned, no-follow directory identities.
  It never resumes a move, undo, or folder removal. Only the recovery journal is
  updated when the filesystem proves completion, non-application, or restored undo.
- `recoveryReport()` returns `RecoveryOperation` values with the original durable
  operation, `completed` / `unapplied` / `undone` / `uncertain` status,
  `blockingTaskID`, explanations, and explicit recovery options. Known completed
  records remain retained even if their files subsequently disappear or cannot be
  identified. Missing grants produce uncertainty and a grant-access option rather
  than inspecting another folder. The History window uses this report for paths,
  explanations, enabled best-effort task/file undo, and explicit empty-folder
  cleanup. `historySnapshot()` remains observational and does not reconcile.
- Journal order and file identity, not names or timestamps, determine precedence.
  Both task and file undo throw `SortError.newerOperation` when a newer active
  operation for the same identity blocks an older operation. Task undo continues
  other safe files but never silently undoes the newer task. Undo retains its
  no-overwrite, identity checking, single-link, and later-content-edit behavior.
- Explicit undo/cleanup alone can remove a recorded, identified empty task-created
  folder. Pre-existing, nonempty, replaced, or unrecorded created folders are not
  removed by reconciliation. A stop between mkdir and saving the created folder's
  identity intentionally leaves an uncertain record and preserves the folder.
- Existing journal decoding and operation schema remain unchanged; this is not a
  journal migration. The original constructor remains source-compatible.
  `TaskCoordinator(bookmarkFile:operationCheckpoint:)` adds an optional synchronous
  throwing diagnostics callback. `OperationCheckpoint` marks durable intent,
  created folder, before/after move, completion, undo intent, after undo move, and
  undo completion boundaries. The default is a no-op. A thrown callback stops the
  task without rollback; real journal persistence remains in use.

## Local evidence — 2026-10-28

Tests use the agreed coordinator boundary, real temporary files, bookmarks,
exclusive renames, durable journal writes, and newly constructed coordinators.
The earlier #4 network-denial restriction was not repeated: normal locked
dependency fetching and integrated builds succeeded.

Observed red → green slices:

1. Reopen removed an identified empty created folder without authorization. A
   real-file test failed that assertion; removing implicit cleanup made it pass.
   The older cleanup test now explicitly requests undo before expecting removal.
2. An older file undo silently moved a newer task's result. After introducing
   the named error, the test failed because no error was thrown and the newer
   result disappeared. Identity-based precedence now blocks both file/task undo;
   the report names the blocking task. Newer undo remains independently usable.
3. Recovery-report assertions initially failed compilation because the API did
   not exist. They now distinguish actual completed/unapplied/missing results,
   retain uncertain intents, and check repeated reopening without mutation.
4. Real-file checkpoint tests initially completed both files rather than stopping.
   Wired checkpoints now stop before a move, after a move, and immediately after
   mkdir; reopen classifies each conservatively, never processes the later file,
   and can undo the identified completed subset.
5. Two pending records for one identity required two reconciliations to settle;
   the second reopen changed persisted journal bytes. Newest-first reconciliation
   settles both in one pass and leaves the journal byte-identical on repeat.
6. A terminal undone record whose file was externally moved back to its former
   result incorrectly offered another undo. The failing report assertions now
   pass: the retained terminal record is uncertain and does not offer undo.

Additional coverage forces **actual** final-save errors by changing the owned
journal directory to mode `0500` immediately after a successful move or undo move.
The OS rejects the completion write. After restoring directory permissions,
reopening first observes the durable `intent` / `undoIntent`, then reconciles
idempotently. The batch correctly counts a moved file rather than a failure with
no change. Undo preserves an in-place later content edit. Explicit subsequent
cleanup removes only the identified empty created folder. A further real-file
test confirms that a newer-task conflict still permits other safe files in the
older task to be restored.

| Check | Result |
| --- | --- |
| Baseline `swift test --filter TidyCoreTests` | 31 reported tests: 30 executed passed, one native provider fixture skipped. |
| Final integrated `swift test` | Core: 39 reported, 38 executed passed, one native provider fixture skipped. Model: 11 executed passed. Total: 49 executed passed, one skipped. |
| `bash scripts/lint.sh` | Passed strict Swift formatting, plist checks and shell syntax. |
| `git diff --check` | Passed. |
| `bash scripts/build-app.sh` after integration merge | Built the sandboxed arm64 app with Metal resources; ad-hoc signing and strict signature verification passed. |

The first small red test also ran through a temporary dependency-free SwiftPM
harness symlinked to the same core sources/tests; all final results above use the
actual integrated package. SwiftPM emitted the existing MLX resource-bundle
"missing creator for mutated node" warning, but completed successfully.

## Open acceptance gaps

Native GUI automation is unavailable. The signed app was built, not launched or
interacted with. Coordinator recreation is not an actual app process restart.

- [ ] Native startup and History presentation, accessible explanations/options,
      original-folder grant renewal, task/file conflict feedback, cleanup and
      keyboard/VoiceOver interaction.
- [ ] Actual process kill, power loss, or filesystem flush failure at mutation /
      persistence boundaries. The tests inject synchronous stops and real write
      denials; they are not power-loss experiments.
- [ ] Signed sandbox denial/revocation and macOS 14 qualification, real provider
      placeholders, supported-volume identity behavior and hostile external
      directory replacement timing (including the identity-check/removal window).
- [ ] Native end-to-end repeated model-generated rename/move chains once #7's
      execution path is integrated. Current repeated-identity coverage uses the
      existing sort boundary with real external repositioning between tasks.

No native acceptance gate is claimed complete and #5 remains open.
