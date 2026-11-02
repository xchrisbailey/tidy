# 8 — Bind mutation to proven objects

Back to [[plans/01-stable-filesystem-identity/overview]].

**Goal:** The shared mutation path enforces continuity at each existing checkpoint;
preserve the safe-undo ADR and local-only state.

**Changes:** `Sources/TidyCore/BatchOperations.swift`,
`Sources/TidyCore/CaseOnlyRename.swift`, `Tests/TidyCoreTests/MutationSafetyTests.swift`.

**Data structures:** Plan/change proofs, task-created-directory proof and pinned
source evidence. Keep exact freshness separately. No global Equatable relaxation.

**Routing:** Shared mutation integration, not a parallel mutation engine.

**Static verification:** Map every current identity comparison to an explicit
verdict; preserve exclusive rename and final descriptor/entry rechecks. Swift/lint.

**Runtime verification:** Root/ancestor/destination swaps; case-only collision;
stale source; qualified drift; missing-proof failure. Preserve the existing
74-nanosecond tests as legacy/unsupported-path refusals rather than deleting them
to obtain a pass. Do not overclaim atomicity against arbitrary hostile timing.
