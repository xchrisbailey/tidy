# 10 — Reverse and clean up only proven originals

Back to [[plans/01-stable-filesystem-identity/overview]].

**Goal:** Qualified drift becomes recoverable without accepting replacements or
removing unrelated directories. Retain safe, best-effort undo and local state.

**Changes:** `Sources/TidyCore/SortOperations.swift`,
`Sources/TidyCore/FilesystemIdentity.swift`, `Tests/TidyCoreTests/SortAndUndoTests.swift`.

**Data structures:** Pinned undo proofs and task-created-folder continuity evidence.
Later file-content edits remain distinct from replacement.

**Routing:** Undo/cleanup integration.

**Static verification:** Recheck root, ancestors, destination and file before and
after the existing durable undo-intent checkpoints. Keep emptiness and ownership
requirements for cleanup. Swift/lint checks pass.

**Runtime verification:** Qualified drift with exact byte/path restoration; same-name
replacement with identical bytes/copied metadata; occupied originals; later edits
to the same object; unsupported/legacy drift refusal. No fallback to a content hash.
