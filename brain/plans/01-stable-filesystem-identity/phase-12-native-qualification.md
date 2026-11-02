# 12 — Recheck the original native failure, separately from TCC

Back to [[plans/01-stable-filesystem-identity/overview]].

**Goal:** Record an actual qualified outcome rather than infer it from tests.
Retain the local-only and safe-best-effort-undo ADR constraints.

**Changes:** A new bounded verification record under `docs/verification/` and an
update to `docs/verification/ticket-15.md`. No new source or global settings.

**Data structures:** Per-check outcome: passed, refused, blocked or unverified;
record filesystem capability/proof scheme and source/artifact provenance.

**Routing:** Authorized native-app observation, not an async-only implementation.

**Static verification:** Documentation names exact qualifications and unsupported
cases. No broad hardware/provider/TCC claim; review source/artifact linkage.

**Runtime verification:** In a uniquely identified test app with synthetic fixtures,
observe root/destination birth rewrite, actual relaunch, explicit undo, file bytes
and scoped cleanup. Recheck replacement rejection. Legacy stranded records remain
legacy; a successful new task does not repair or qualify old history. Permission
revocation remains a separate blocked gate; preserve all existing owner deferrals.
