# 11 — Gate activation on durable and replacement safety

Back to [[plans/01-stable-filesystem-identity/overview]].

**Goal:** Enable no new production proof until persistence and every authority role
are reviewed together. Follow both ADRs; no release/CI action.

**Changes:** `Tests/RecoveryTestWorker/RecoveryTestWorker.swift`,
`Tests/TidyCoreTests/ProcessRecoveryTests.swift`, `scripts/release-tests.sh`.
Activation itself is the reviewed configuration of the phase-2 proof module;
if it needs additional source edits, split those into a separately reviewed phase.

**Data structures:** Child-process evidence for versioned journals and proof; no
different parent identity substituted for same-executable bookmark restoration.

**Routing:** Local process qualification and independent code review.

**Static verification:** Search every FileIdentity equality/construction and snapshot
comparison against the inventory in testing.md. Confirm no partially migrated path
or old-binary schema bypass. Lint/type checks and independent review.

**Runtime verification:** All eight SIGKILL checkpoints with new proof; mixed legacy
records; namespace/proof loss; replacements including synthetic equal-legacy-tuple
distinct incarnations; upgraded-record old-binary refusal. Run full debug/optimized
suites. Finite actual inode-reuse stress does not replace the capability contract.
