# 5 — Preserve ancestor and content-read authority

Back to [[plans/01-stable-filesystem-identity/overview]].

**Goal:** Strong continuity must not weaken no-follow traversal or stale-input
rejection. Apply the local-only and safe-undo ADRs.

**Changes:** `Sources/TidyCore/RecursiveScope.swift`,
`Sources/TidyCore/ContentInspection.swift`, `Tests/TidyCoreTests/ContentNamingTests.swift`.

**Data structures:** Descriptor-bound ancestor proof chain; ExactObservation for
content freshness remains distinct from object continuity.

**Routing:** Filesystem authority and content-read integration.

**Static verification:** Audit every pre/post-open and during-read check; no
capability lookup opens placeholder contents or follows symlinks. Swift/lint pass.

**Runtime verification:** Ancestor replacement, same-object stale content, qualified
ancestor metadata drift, hard-link/symlink refusal, and cloud-only read exclusion.
Do not claim bounded arbitrary OS I/O latency from cooperative checks.
