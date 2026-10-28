# Ticket #13: persistent undo history

## Scope and application seam

The native **Undo History** window is available from the Window menu and shares
the app's `TaskCoordinator`. The approved testing seam is that coordinator's
public history/undo API, using real temporary files, real bookmarks, and reopened
coordinators. There is no second history store.

- `historySnapshot()` returns persisted `FileOperation` records and
  `recordBytes`: logical bytes of `operations.json`, not allocated filesystem
  blocks or total Application Support usage. Grants, models and lock bookkeeping
  are excluded. A never-created journal reports zero; the durable empty JSON array
  after clearing occupies two bytes.
- `FileOperation.originalPath` and `resultingPath` expose the recorded locations.
- `clearHistory(confirmingUndoLoss:)` rejects `false` with
  `HistoryError.confirmationRequired`. The native destructive alert explains
  permanent task/file undo loss, including interrupted changes, and offers Cancel.
  Clearing atomically saves an empty journal under the existing journal lock. It
  never traverses user folders or model storage, and keeps folder grants.
- `undoTask(_:)` and `undoFile(_:)` remain the existing coordinator entry points.
  The initial integrated journal has one operation per task; #4 owns batch task
  grouping. Later operation types must extend these records/the same window, not
  introduce another history database.

Browsing is deliberately observational: unlike `undoHistory()`, it does not
reconcile interrupted operations or clean up task-created user folders. An
interrupted outcome stays visibly uncertain until the existing coordinator's
recovery/undo path checks identity. Records contain paths, identities and recovery
state, not file contents/excerpts. There is no automatic expiry, and the view
explicitly says history is not a backup.

## Local evidence (2026-10-28)

Ancestry confirmed against `integration/tidy-v1` at `eb7e84b` before work.
Two red-green slices:

1. `HistoryTests.historyReopensWithPathsOutcomesAndMeasuredRecordStorage` first
   failed because `historySnapshot()` did not exist, then passed. It checks
   persisted locations/outcome after reopening, exact storage bytes against the
   file on disk, no private document content in the journal, actual unchanged
   resulting contents, and individual-file undo through the existing coordinator.
2. `HistoryTests.clearRequiresConfirmationAndOnlyDiscardsRecoveryRecordsAcrossReopen`
   first failed because the confirmation/clear API did not exist, then passed.
   It checks refusal without confirmation, retention after refusal, empty records
   and exact empty-journal usage after clearing/reopening, loss of task/file undo,
   unchanged resulting bytes, inode and modification date, unchanged original
   folder entries, no recreated original file, and unchanged bookmark, write
   grant and unrelated model bytes.

`swift test`: 21 tests reported successful, including the real-provider test
explicitly skipped because no real provider fixtures were supplied.
`bash scripts/lint.sh`: passed (strict Swift formatting, plist/entitlements, shell
syntax). `bash scripts/build-app.sh`: passed; sandboxed arm64 app built and
ad-hoc signed. No dependencies, network, or CI were added/used.

## Manual acceptance still open

Native GUI automation is unavailable in this session. Building and command-line
tests are **not** evidence of sandboxed picker consent, relaunch grants or native
alert/accessibility behavior. The user approved provisional downstream work while
those earlier acceptance gaps remain open. Do not close #13 on this evidence alone.

On a disposable folder in the sandboxed app:

1. Run a supported task. Open Window → Undo History; verify original/resulting
   full paths, task/file outcomes, usage and both undo controls.
2. Quit/relaunch the same signed build. Verify retained history and usage. Try
   file undo and task undo, including an occupied-original conflict. Verify no
   overwrite and the visible explanation. Re-grant the original folder as needed.
3. Open Clear History, read the undo-loss explanation, cancel; verify records and
   files unchanged. Confirm clearing; verify the empty state and two-byte record
   usage, and that previous undo controls are unavailable.
4. Quit/relaunch again. Verify empty history; compare user folder paths, bytes,
   identities/modification times and unrelated model storage before/after clear.
5. Qualify VoiceOver, keyboard navigation, long paths, multiwindow refresh and
   the destructive alert's cancel/default behavior on supported macOS versions.
