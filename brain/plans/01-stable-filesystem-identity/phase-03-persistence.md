# 3 — Version history and define downgrade behavior

Back to [[plans/01-stable-filesystem-identity/overview]].

**Goal:** Persist proof without silently blessing legacy records or letting an old
binary ignore new safety fields. Follow the safe-undo ADR; keep evidence local.

**Changes:** `Sources/TidyCore/OperationJournal.swift`,
`Sources/TidyCore/History.swift`, `Tests/TidyCoreTests/RecoveryTests.swift`.

**Data structures:** Versioned journal envelope, legacy identity variant and
qualified proof variant. Preserve operation IDs, ordering, task IDs and ancestor
authority. Define safe read-only inspection of unsupported records. Activate new
writing only with the final migration gate, not halfway through call-site routing.

**Routing:** Serialization and durable-state implementation.

**Static verification:** Review old-array decoding, unknown versions, schema limits,
atomic persistence/locking and unchanged clear-history scope; run lint/type checks.

**Runtime verification:** Legacy round-trip; new envelope round-trip; unknown or
malformed proof refuses mutation; old-binary decoder rejects new format; durable
interruption never publishes partially upgraded authority. Do not backfill proof
after drift merely because current metadata appears plausible.
