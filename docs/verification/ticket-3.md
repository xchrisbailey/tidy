# Ticket #3: one-file sort and durable undo

## Local evidence — 2026-10-28

Started `ticket/3-sort-and-undo` exactly at integration tip `bd97bb3` (#2).
Proceeding provisionally does not resolve #2's native acceptance gaps or close
either issue. The accepted local-model ADR does not change this explicit,
deterministic sort slice; no model lifecycle or broader request handling is added.

| Check | Result |
| --- | --- |
| Baseline `swift test` | Six inventory tests passed; the real-provider fixture test was explicitly skipped. |
| Final `swift test` | Eighteen test functions passed, including parameterized safety cases; one real-provider test explicitly skipped. |
| `bash scripts/lint.sh` | Strict Swift formatting, packaging plists, and shell syntax passed. |
| `bash scripts/build-app.sh` | Sandboxed arm64 development bundle built, ad-hoc signed, and strict signature verification passed. |
| `codesign --display --entitlements - .build/Tidy.app` | Sandbox, user-selected read-write access, app-scoped bookmarks; no network entitlement. |

No new dependencies, CI, network requests, telemetry, or ticket closure.

## Red → green evidence

Tests use the agreed public task-coordinator boundary, real temporary files,
and a newly initialized coordinator for reopened history/undo.

1. Sort → reopen → task undo initially failed compilation because the public
   operation/grant/history APIs did not exist; it passed after implementation.
2. Replacing the inventoried source with the same name and size initially moved
   the replacement. It now refuses it before creating a destination folder,
   using device/inode/birth-time identity and a metadata snapshot.
3. Reopening a durable intent with the file already moved initially left it as
   an intent; it now reconciles to completed and permits safe undo.
4. Reopening an undo intent with the file restored initially left the task-created
   empty folder behind; it now reconciles to undone and cleans that folder.
5. A missing resulting folder initially reported an occupied/unsafe destination;
   it now reports uncertain identity without moving another file.
6. A corrupt journal name containing NUL initially passed validation and reached
   the filesystem as a truncated name. It now rejects history before mutation.

Additional passing safety coverage exercises read-grant rejection, unsupported
requests, concurrent submissions, occupied original/destination locations,
destination symlinks, same-name replacement files, later in-place edits,
preexisting destination folders, and task-created folders containing later files.

Interrupted-journal fixtures serialize an actual operation and place its public
state at a documented interruption boundary while retaining real file identities.
They are recovery-state tests, not actual process-kill or power-loss experiments.

## Interface and persistence notes

- `selectFolder`/`restoreFolder` retain read-only inventory bookmarks.
  `selectFolderForWriting` deliberately creates a separate scoped write grant.
  Old read bookmarks are never upgraded implicitly. Native UI has a distinct
  **Grant Write Access…** picker and explains the scope before selection.
- `sortByType(request:)` accepts only “Sort by type” (case/whitespace normalized),
  with one eligible direct child of a supported extension. The coordinator stores
  the inventory snapshot; refresh after external edits. It moves immediately,
  without preview, preserving the name and file object rather than copying bytes.
- `undoHistory`, `undoTask(UUID)`, and `undoFile(UUID)` are public. This slice has
  one operation per task, so task and file IDs coincide. Re-grant the original
  folder when undoing history for a folder other than the saved write grant.
- Adjacent to the supplied bookmark file are `operations.json`, `operations.lock`,
  and `<bookmark filename>.write-grant`. The journal stores paths, actual file and
  folder identities, intent/completion states, and identified created folders,
  not extracted contents. Private temporary writes are flushed before atomic
  publication; the parent directory is flushed too. Move directories are flushed
  before recording completion. Mutation and reconciliation hold the journal lock.
- Directory-relative, no-follow handles anchor operations. Moves use macOS
  `renameatx_np(..., RENAME_EXCL)`; identities are checked before/after moving.
  Undo never uses a matching filename or matching bytes as proof of identity.
  Later in-place edits survive; replacement-by-save gets an identity conflict.
- Reconciliation leaves ambiguous intents unresolved. A stop after folder creation
  but before recording its identity may leave a folder behind: ownership is not
  inferred from its name. Cleanup uses recorded folder identity and atomic empty-
  directory removal; existing and nonempty folders are preserved.
- No inference or model-lifecycle interface was added. The separate model worker
  can keep its lifecycle independent of these coordinator operation APIs.

## Unverified acceptance gates

Native GUI tools were unavailable. The signed bundle was built and inspected,
but **not launched or interacted with**. Automated bookmark/reopen tests run
outside the app sandbox and reopen a coordinator within the same test process.
They do not establish native picker authorization or actual app-restart behavior.

- [ ] Launch the signed bundle with a disposable folder containing one `notes.txt`.
      Inspect with a read grant; **Run** must request a deliberate write grant,
      without moving files. Check picker cancellation and the exact scope copy.
- [ ] Grant write access through the new picker; submit “Sort by type.” Check the
      native result, unchanged bytes/name, `Documents/notes.txt`, and no preview.
      Check an unsupported request and a folder with multiple eligible files.
- [ ] Quit and reopen the same signed build without rebuilding. Check persisted
      history and try task undo; repeat with individual-file undo. Check both
      occupied-original and replaced-file conflicts without overwriting anything.
- [ ] Check real sandbox write denial/revocation, old read-grant migration, folder
      reselection, and history visibility when the remembered folder is unavailable.
- [ ] Check native responsiveness while submitting/undoing; controls should prevent
      overlapping mutations. Inventory cancellation remains available, but a
      committed filesystem mutation is not presented as cancellable.
- [ ] Qualify actual process interruption/power-loss behavior and concurrent external
      filesystem changes, including rapid directory replacement. Recovery fixtures
      and immediate identity checks are not proof of every hostile timing window.
- [ ] Repeat native flows on macOS 14 and qualify supported filesystems/providers.
      No provider fixture was supplied; the inherited provider test remains skipped.

These are open manual gates, not completed checks. No issue was closed.
