# #12 — model storage and replacement verification

2026-10-28. Provisional downstream implementation from `0ecf6a9`; **leave #12 open**. #6's hardware, distribution, GUI, and planning-quality gates remain open. No CI/cloud inference, new dependencies, automatic model download, or primary task-flow catalog was added.

## Lifecycle and integration API

The existing observable `ModelSetup`, manifest/hash verification, same-volume promotion, URLSession resume/cleanup, and MLX runtime remain the only mechanism. The standalone native Local Model Storage window is available from the application menu alongside setup. Installed revisions show measured file bytes and active/not-active status; incomplete transfers have separate usage, consented resume, and cleanup. Removal has an explicit native confirmation, and active removal immediately withdraws readiness before waiting for runtime unload/deletion. File bytes are logical sizes, not APFS physical allocation or OS-owned URLSession temporary storage.

- `state` remains the primary task readiness API. It stays `.ready` while a replacement is preparing or fails, as long as the original runtime remains active.
- `activity` independently reports replacement progress, pause, cancellation, and sanitized failure. `activeManifest` identifies the working revision; `manifest` identifies the current setup/replacement target, **not necessarily the active model**.
- `installedModels`, `partialModels`, `partialBytes`, and `refreshStorage()` expose storage inventory. Each stored revision has its immutable manifest and measured bytes. Installed does not imply ready.
- `replace(revision:consent:)` accepts only the app-supplied catalog (`manifest` plus `replacements` at initialization). `remove(revision:consent:)` requires explicit consent. `cancel(revision:)` can clean a known paused candidate after relaunch; ordinary `cancel()` waits for the current writer/runtime preparation to stop before cleanup.
- `LocalModelRuntime.loadAndCheck(directory:commit:)` is transactional: prepare/check candidate while retaining the old container, check cancellation, invoke the synchronous throwing selection commit, then switch the container without suspension/further throwing work. The directory-only overload remains available. Runtime implementers must implement the transactional requirement; existing test doubles were updated.
- The atomic `active-revision` file records selection only after native inference succeeds. Failure to persist selection cannot switch the runtime. Relaunch resolves only bundled manifests, rehashes all files, and performs native inference; no persisted ready flag or network restore exists.

One active container pointer is selected at a time. An in-flight generation retains its original container until it finishes; replacing the pointer does not cancel a working task. Verified old files remain until explicitly removed. The shipping catalog still has **one** reviewed candidate, not a fabricated newer model. Future app-curated revisions must retain the relevant trusted manifests in the catalog for inventory/restore. No arbitrary import or tuning controls exist.

## Agreed seam and red/green

Agreed observable model lifecycle seam, controlled transfers/native-load boundary, and real temporary storage fixtures; no private-state assertions. The primary coordinator/main task UI belongs to concurrent #4 and was not edited here.

1. Wrote consent/replacement/selected-relaunch/removal test first. `swift test --filter replacementRequiresConsentAndKeepsWorkingModelUntilActivation` failed to compile because replacement/catalog/storage APIs did not exist. Minimal lifecycle/storage implementation made it pass.
2. Added pause/relaunch/resume/cancellation coverage at that same seam. The red run failed on missing observable partial-byte reporting; implementation added installed/partial inventory and cleanup reporting, then passed.
3. Added regression cases for insufficient capacity, transfer failure, corrupt same-sized replacement, native activation failure, and failed selection persistence. All preserve the original public readiness, loaded runtime revision, and actual original files. Relaunch restores the original selection except in the deliberately externally corrupted selection-file fixture.

The prior #6 lifecycle/real-HTTP resume tests remain green, including real resumed 206 and ignored Range/changed validator replacement, truncated responses, SHA mismatch, resume invalidation, and writer-quiescent cleanup. No test fills the developer's disk.

## Local native evidence and checks

`bash scripts/model-smoke.sh` passed in an ad-hoc-signed diagnostic app bundle, network denied and original build-product reads denied. It reused `~/Library/Application Support/Tidy/QualificationModels` and the already approved exact artifact; **no second large download**. The smoke exercised native candidate preparation with a failed selection commit, cancellation during preparation, subsequent synthetic rename inference on the original container, successful checked replacement using the same artifact, and subsequent inference. This supplements fixture-version replacement; it is not evidence for a second production revision.

Observed on the existing M4 Max / 36 GB machine:

- Full offline rehash/load/readiness: 3.503 s.
- Synthetic rename after failed/cancelled replacement: 0.364 s, exact expected complete operation.
- MLX peak across replacement preparation: 4,694,835,504 bytes; physical footprint after recovery: 2,671,889,912 bytes.
- Generation cancellation/drain: 0.0101 s; subsequent inference and successful replacement inference passed.

Initial local checks: `swift test` passed 11 model tests (five failure cases and two real-HTTP resume modes) plus 21 core tests; the existing native File Provider placeholder test was skipped. `bash scripts/lint.sh` and `git diff --check` passed. Upstream's existing resource-bundle mutated-node warning remains.

## Remaining gates

- Native GUI unavailable: manually verify storage menu/window, dialogs, keyboard/accessibility behavior, visible readiness while replacing, pause/resume, cancellation, removal, and relaunch in the packaged app.
- Lower-memory Apple silicon and macOS 14 replacement pressure are unqualified. Keeping the old container while preparing the candidate increases peak allocation; the observed 36 GB machine does not qualify the provisional 16 GB floor.
- No second reviewed production revision exists. Different-version behavior is covered by real-file fixtures; native checks reuse the exact existing candidate without claiming qualification of another artifact.
- Final distribution/archive execution, deliberate process termination during replacement, OS resume-temp eviction, and downstream complete task-planning quality remain release gates. Atomic selection and offline re-verification provide crash-safe readiness; no native GUI/process-kill evidence is claimed.
