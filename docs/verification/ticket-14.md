# #14 — private diagnostic export

2026-10-28. Provisional implementation, not acceptance closure. Started clean on
`ticket/14-private-diagnostics` at the requested `51ae6fd`. A merge of
`integration/tidy-v1` before final verification reported already up to date at that
same commit. No dependencies, CI, cloud services, telemetry, downloads of model
weights, primary user documentation or issue status changes.

## Public boundary and privacy

- `TaskCoordinator.exportDiagnostics(to:modelState:)` explicitly writes a JSON
  artifact to the caller's destination. The native **Private Diagnostics** window,
  accessible from Help and the main window, explains the contents and uses
  `NSSavePanel`. Save success, cancellation and failure feedback never interpolates
  the destination or an underlying error. Nothing submits or transmits the file.
- Schema 1 contains only `schemaVersion`, numeric macOS major/minor/patch,
  `DiagnosticModelState`, and fixed-key integer counters. Model state is a closed
  enum, not the setup failure's associated reason. No bundle metadata, arbitrary
  strings, error descriptions, nested errors, timestamps, task IDs, folder grants,
  filenames, paths, prompts, model replies or evidence are accepted by this schema.
- `recordDiagnostic(_:)` accepts only `DiagnosticCode`. Coordinator planning,
  batch execution, recovery reporting, startup undo-history loading and task/file
  undo record safe categories automatically. Session counters saturate at one
  million. A model-not-ready submission records `modelUnavailable`.
- Inspection codes are counted when the complete content plan returns; no
  `FileOutcome`, its name/explanation, or `InspectionEvidence` is serialized.
  `InspectionCode` remains owned by the content-inspection implementation, unchanged
  here. No PDF/helper implementation was edited.
- Export observes retained undo history without reconciliation or mutation of user
  files, counting only the closed operation states. Unavailable/busy history is a
  fixed `historyUnavailable` flag. After reopening, session failure counts are gone;
  durable state counts remain available. This intentionally adds no persistent
  diagnostic log, event history or extracted-text storage. Normal undo history
  continues to retain ordinary paths/names required for undo, not excerpts.
- Save errors are reduced to `DiagnosticExportError.couldNotSave`, with a fixed
  explanation and no associated underlying error. Destination paths never become
  artifact fields. The UI warns that choosing a sync-managed location may cause
  the user's existing sync service to sync the artifact.

## Red → green at the agreed coordinator/export seam

Tests use actual temporary folders, selected-folder bookmarks, ordinary files,
durable recovery records and exported files reopened from disk. Model completions
and synchronous operation checkpoints control failures; persistence is not mocked.

1. Initial export test failed compilation because `exportDiagnostics` did not
   exist. Added the allowlisted schema/export and planning model-failure counter;
   the real artifact test passed.
2. Parameterized failure test then failed its ordinary-task, post-move interruption
   and recovery counter assertions. Added coordinator execution/recovery recording;
   all passed. Invalid model JSON and invalid UTF-8 inspection abstention were
   exercised through planning, not by calling diagnostic internals.
3. Typed model-state export failed compilation before adding that API and closed
   enum. It now preserves a safe failure state without the setup reason string.
4. Occupied-original-location undo failed the recovery-counter assertion before
   coordinator undo recording; it now passes while preserving the occupied file.

Fixtures carry unique sensitive markers in filenames, task text, document bytes,
model JSON, error descriptions, nested `NSError` metadata and export destinations.
Every failure artifact is read from disk and checked for marker/path exclusion.
The top-level schema is also checked. A valid inspected text fixture proves the
content marker actually reached the local naming prompt, then throws a private
model error; neither artifact nor retained settings/history contains its excerpt.
Post-move interruption leaves a real pending record: a fresh coordinator reconciles
it and exports `history_completed` without names/contents. This is coordinator
recreation, **not an actual process-kill/restart test**. Write-failure artifacts use
an invalid child destination and verify the public error contains no private path.
Persistent settings/history files are scanned for excerpt markers. Corrupt-journal
fixtures are excluded from that scan because the test deliberately writes the
marker into the journal to cause the recovery failure.

## Local checks

| Command | Result |
| --- | --- |
| `swift test --disable-automatic-resolution` | Passed: 85 reported core tests, one real File Provider fixture skipped (84 executed); 11 model tests executed. 95 executed total, including two diagnostic test functions with seven parameterized failure cases. |
| `bash scripts/lint.sh` | Passed strict Swift formatting, three plist checks and shell syntax. |
| `git diff --check` | Passed. |
| `bash scripts/build-app.sh` | Passed arm64 packaging, bundled Metal resources, ad-hoc signing and strict signature verification. No GUI launch/interaction. |

Approved locked dependency resolution fetched existing dependencies from cache;
no approval blocker occurred. Existing upstream MLX mutated-resource-node warnings
remain nonfatal. Tests use controlled local completions; no real-model inference
qualification was claimed or needed for this exporter-only change.

## Manual/native acceptance still open

Native GUI automation is unavailable. Built app behavior is not treated as tested.

- [ ] Open Private Diagnostics from Help and the main window after model, planning,
      execution and recovery failures; verify understandable presentation and
      keyboard/VoiceOver access.
- [ ] In the signed sandbox app, save through the native panel, inspect the actual
      artifact, cancel the panel, decline overwrite and trigger a genuine destination
      permission/revocation failure. Confirm feedback never displays its path/error.
- [ ] Quit/relaunch or actually interrupt the app process during execution, reopen
      history, and export; confirm session-only counts versus durable state counts.
- [ ] Verify ordinary cleanup offline/account-free on qualified hardware and macOS
      14; verify no automatic diagnostic network traffic/crash submission. Existing
      broader model/recovery/inspection acceptance gaps remain open.

No issue or native acceptance gate is closed by this work.
