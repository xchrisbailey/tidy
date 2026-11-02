# 9 — Preserve conservative recovery and operation ordering

Back to [[plans/01-stable-filesystem-identity/overview]].

**Goal:** Metadata rewriting cannot hide a newer operation on the same object.
History stays passive under both existing ADRs.

**Changes:** `Sources/TidyCore/Recovery.swift`,
`Sources/TidyCore/HistoryUndo.swift`, `Tests/TidyCoreTests/RecoveryTests.swift`.

**Data structures:** Three-way recorded continuity verdict; recovery result that
keeps unavailable proof distinct from proven replacement and absent destination.

**Routing:** Recovery/history integration.

**Static verification:** Audit recorded-to-recorded as well as live-to-recorded
comparisons. Mixed/unknown proof cannot silently remove ordering blocks. Swift/lint.

**Runtime verification:** Newer-operation chain across birth rewrite; mixed legacy
history; missing proof; root replacement; repeated passive recovery. No auto-resume,
implicit proof upgrade or journal rewrite that changes historical authority.
