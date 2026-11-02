# 6 — Capture inventory and expanded-plan proof coherently

Back to [[plans/01-stable-filesystem-identity/overview]].

**Goal:** Planning observations and mutation proof refer to the same pinned objects;
preserve local-only operation and no automatic unsafe recovery.

**Changes:** `Sources/TidyCore/TaskCoordinator.swift`,
`Sources/TidyCore/MetadataPlanExpansion.swift`, `Tests/TidyCoreTests/RecursiveScopeTests.swift`.

**Data structures:** Inventory snapshots with separate exact freshness/proof;
expanded changes carrying required destination and ancestor proofs.

**Routing:** Inventory/plan-capture integration.

**Static verification:** Required proof cannot disappear into optional absence;
no capability/file-ID capture by an unbound path. Swift/lint pass.

**Runtime verification:** Scope counts/exclusions, descriptor/path swaps, destination
replacement, unsupported-proof capture and qualified directory metadata rewrite.
Continue to reject stale plans; do not infer consent from the new identity.
