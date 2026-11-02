---
id: 1
created: 2026-11-01
status: active
execution: phase-01-blocked
---

# Stable filesystem identity without timestamp tolerance

## Execution checkpoint

Phase 1 produced diagnostic capture/tests and
[bounded host evidence](../../../docs/verification/stable-v1-identity-feasibility.md).
Ordinary/sandbox capture, metadata rewriting, replacement and read-only remount
checks pass on the current host. Independent review recommends **STOP**: durable
volume-incarnation safety across clone/restore/rollback remains unproved. Phase 2
and production activation are paused; no identity policy was changed.

[Subsequent primary-source research](../../../docs/verification/stable-v1-volume-incarnation-research.md)
did not supply the missing public lifetime/ambiguity contract. Keep STOP; more
same-host stress loops do not resolve that documentation/proof gap. Owner review
or a supported platform contract is needed before changing the design scope.

## Context and principles

The [birth-time investigation](../../../docs/verification/stable-v1-birthtime-investigation.md)
reproduced metadata rewriting outside Tidy. Exact birth-time identity checks
correctly refuse uncertainty but can prevent legitimate undo. This plan designs
an alternative proof, not a tolerance patch or an implemented fix.

`brain/principles.md` does not exist. No new project-wide principles are invented.
This plan follows the actual repository decisions:

- [[docs/adr/0001-keep-v1-file-processing-local]] — all identity evidence and
  processing remain local; no account, telemetry, cloud fallback or dependency.
- [[docs/adr/0002-execute-clear-requests-with-persistent-undo]] — durable history,
  best-effort undo and refusal rather than unsafe reversal remain core.

The wikilinks name repository-root documents; ordinary relative links above work
without a knowledge-base renderer. Follow `GLOSSARY.md` and root `AGENTS.md`.

## Scope and definition of done

Cover every authority role: selected root, write-grant root, file, source ancestor,
destination and task-created folder; recovery, operation precedence and cleanup.
Keep content freshness, provider eligibility and permission grants independent.

Success requires demonstrably safe recovery/undo after birth-time rewriting on a
qualified filesystem, including a fresh process, while rejecting actual
replacements, reused identities and unsupported proof. Unsupported volumes and
legacy records keep strict refusal. Never imply the currently stranded native
task has become recoverable merely because a new mechanism is implemented.

Out of scope: TCC revocation, other #15 gates, supported-hardware declarations,
new model downloads, global permissions, automatic history repair, xattr stamping
of user files, filesystem-wide searches and weakening final no-follow/race checks.

## Alternatives and recommendation

| Approach | Decision |
| --- | --- |
| Round/tolerate birth time or match pathname/inode/hash alone | Reject: broadens identity without proving continuity; hashes also reject legitimate edits and can match replacements. |
| Retained descriptors, opaque Foundation IDs or bookmarks | Retain descriptors for live operations and bookmarks for access/location. Alone they do not establish restart-safe durable identity. |
| Random/signed xattr markers | Reject as authoritative proof: clone/copy/replay can duplicate markers; alters user metadata. |
| Qualified volume namespace + full-width non-recycled object ID | Recommended **feasibility candidate**, not yet an enabled backend. |

Apple's `sys/attr.h` documents `VOL_CAP_FMT_PATH_FROM_ID` as implying persistent,
non-recycled IDs. Require the bit in **both valid and supported capability masks**;
`PERSISTENTOBJECTIDS`, an APFS label, a successful lookup or monotonic observed
inodes alone is insufficient. Use the full `ATTR_CMN_FILEID` on 64-bit-ID volumes.
Do not treat the high half of a legacy object ID as a generation counter.

Require a persistent volume namespace as well. A UUID is a candidate namespace,
not an anti-forgery/rollback attestation. Phase 1 must define and validate volume
incarnation, clone/restore/rollback/remount and provider semantics. If the tuple
cannot distinguish supported cases safely, **stop before enabling it**. Retain
strict legacy behavior, record the blocker and consider guidance-only improvement.

Do not require root-only `st_gen` or native file-handle operations. Do not use
`fsgetpath` to expand authority outside a selected root.

## Threat and trust contract

The intended protection is against external entry replacement, atomic safe-save,
directory swapping, inode reuse and copied metadata during normal filesystem
operation. Object continuity does not prove content freshness or user consent.
Descriptor-relative/no-follow lookup, single-link restrictions, exclusive rename,
ancestor validation and final name-to-descriptor checks remain mandatory.

Do not silently exclude disk clone/restore/snapshot rollback from an existing
promise. Phase 1 must determine what can be detected and explicitly return
unproven for unsupported/ambiguous namespaces. No software tuple authenticates a
hostile kernel or a disk image deliberately spoofing its identity; claims must
state that trust limit without weakening ordinary replacement safety.

## One internal proof module

Introduce an internal `FilesystemIdentity` module at the descriptor-capture seam.
Its interface captures evidence, verifies a current pinned object, verifies an
entry-to-descriptor binding and compares continuity between recorded proofs.
Outcomes are explicit: **same / different / unproven**, never Boolean fallback.

The implementation owns capability discovery, backend choice, exact legacy
observations and versioned durable proof. It does not own sandbox grants, content
eligibility/freshness, journals or moves. This centralizes policy without a
generic filesystem abstraction or a public coordinator dependency-injection API.
Use a narrow internal test seam for capability/identity observations that cannot
be forced deterministically on real APFS; production and integration tests still
exercise real descriptors and operations.

Do not overload `FileIdentity.==` with tolerance or optional-proof fallbacks.
Separate structural observation equality from authority decisions. Missing proof
must not compare equal to an absent destination. Snapshot freshness remains exact
until explicitly redesigned and independently justified.

## Persistence and activation

Version journal and write-grant formats explicitly. Existing array journals remain
readable as legacy strict identities. New saves use an envelope that old binaries
reject, rather than silently ignoring proof fields. Unknown/invalid proof blocks
mutation; preserve safely decodable history for inspection where possible.

Do not backfill historical strong proof from a current inode, regrant or corrected
timestamp. Compare mixed legacy/new records conservatively; unproven overlap must
not remove a newer-operation block. Existing file edits remain undoable only when
object continuity is proven; content-based planning still rejects stale input.

Preparatory phases preserve runtime behavior. Migrate all authority roles before
activating the new backend; do not release partially converted mutation paths.
The versioned write path, old-binary downgrade behavior and all call sites form
one reviewed activation gate. Unsupported capability is not an execution error
to catch and replace with inode-only matching.

## Phases

1. [[plans/01-stable-filesystem-identity/phase-01-feasibility]] — stop/go proof gate.
2. [[plans/01-stable-filesystem-identity/phase-02-proof-module]] — internal proof interface.
3. [[plans/01-stable-filesystem-identity/phase-03-persistence]] — versioned records and downgrade safety.
4. [[plans/01-stable-filesystem-identity/phase-04-write-authority]] — root/write-grant proof.
5. [[plans/01-stable-filesystem-identity/phase-05-ancestors-content]] — recursive and content authority.
6. [[plans/01-stable-filesystem-identity/phase-06-inventory-expansion]] — descriptor-bound inventory/plans.
7. [[plans/01-stable-filesystem-identity/phase-07-planning-roots]] — remaining planning gates.
8. [[plans/01-stable-filesystem-identity/phase-08-mutation]] — shared mutation proof checks.
9. [[plans/01-stable-filesystem-identity/phase-09-recovery-precedence]] — continuity and ordered history.
10. [[plans/01-stable-filesystem-identity/phase-10-undo-cleanup]] — undo and scoped empty cleanup.
11. [[plans/01-stable-filesystem-identity/phase-11-process-activation]] — crash/migration activation gate.
12. [[plans/01-stable-filesystem-identity/phase-12-native-qualification]] — reproduce and record actual behavior.

Twelve small phases keep individual change sets bounded; phases 4–10 are not
independent release approvals. Stop and revisit this plan if evidence changes.

## Verification, sources and skills

See [[plans/01-stable-filesystem-identity/testing]] for the concrete evidence gates
and primary-source limits. Final local commands: `swift test --disable-automatic-resolution`,
`bash scripts/release-tests.sh`, `bash scripts/lint.sh`, `git diff --check`.
Real provider/native validation requires the existing authorized disposable paths;
no skipped test becomes a pass. No CI or release action is authorized by this plan.

Applicable skills: `codebase-design` (module/seam), `diagnosing-bugs` (actual
reproduction), `tdd` (implementation), `security-audit` (focused safety guidance,
not a full audit), `computer-use` (native qualification), `code-review` (pre-activation
review). Existing skills cover the domain; none was installed. Use the configured
coding agent; no specific model selection or new toolchain is required.

This plan does not implement or commit anything. Existing uncommitted drift tests
and verification documents are preserved for separate review.
