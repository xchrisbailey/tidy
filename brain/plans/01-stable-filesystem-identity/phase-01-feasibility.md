# 1 — Prove a usable durable identity contract

Back to [[plans/01-stable-filesystem-identity/overview]].

**Status: BLOCKED at the exit gate.** See
[the recorded feasibility results](../../../docs/verification/stable-v1-identity-feasibility.md).
Diagnostic implementation exists, but capability/tuple stability is not volume
incarnation proof. Independent review did not approve a stronger backend. No
production migration or subsequent phase is authorized by a passing capture test.

**Goal:** Establish a stop/go decision before changing production identity.
Apply the local-only and safe-best-effort-undo ADRs cited in the overview.

**Changes (at most three files):** `Package.swift`, a new isolated
`Tests/IdentityTestWorker/IdentityTestWorker.swift`, and a new
`Tests/TidyCoreTests/FilesystemIdentityQualificationTests.swift`. Keep the harness
diagnostic; no production activation or public interface change.

**Data structures:** CapabilityEvidence, VolumeNamespaceEvidence and a bounded
qualification result. Read capabilities, persistent volume UUID and full file ID
from the same no-follow descriptor/volume context; record unavailable distinctly.

**Routing:** Architecture judgment plus native Darwin adapter work.

**Static verification:** Confirm SDK availability for macOS 14, returned attribute
layout/length handling, both capability masks, and no privileged/private interface.
Review documented ID lifetime and namespace/clone/restore assumptions.

**Runtime verification (five groups):** (1) ordinary-user and real-sandbox capture;
(2) file/directory rename and birth rewrite; (3) replacement/clone/delete-recreate;
(4) fresh process and authorized remount/restart; (5) duplicate/ambiguous volume
namespace and missing capabilities. Finite reuse stress supplements the documented
guarantee, not proves it. Do not reboot or mount other disks without authorization.

**Exit gate:** Independently review the evidence. If durable non-recycling proof or
namespace safety cannot be established, stop; do not continue to an enabled backend.
