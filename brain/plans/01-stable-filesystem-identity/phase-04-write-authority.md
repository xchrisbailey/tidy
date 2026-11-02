# 4 — Keep consent separate from root continuity

Back to [[plans/01-stable-filesystem-identity/overview]].

**Goal:** A valid bookmark grants access to a candidate, not proof it is the
recorded root. Preserve local-only processing and safe best-effort undo.

**Changes:** `Sources/TidyCore/SortOperations.swift`,
`Sources/TidyCore/TaskCoordinator.swift`, `Tests/TidyCoreTests/SortAndUndoTests.swift`.

**Data structures:** Versioned WriteGrant using RecordedIdentity; scoped root
capture tied to an opened descriptor. Keep real security-scope acquisition and
permission failure independent from continuity. Keep new writing inactive until
all phases are ready; old binaries must reject upgraded grants.

**Routing:** Authorization/root integration.

**Static verification:** All selection/root checks cross the proof interface;
read grants do not become writes. Review inventory capture ordering and lint/build.

**Runtime verification:** Read-only write refusal; qualified root birth rewrite;
wrong-root regrant; legacy root mismatch; denied access. Regrant must not authorize
old history for a replacement or silently resume work.
