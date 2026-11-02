# 2 — Centralize identity evidence and verification

Back to [[plans/01-stable-filesystem-identity/overview]].

**Goal:** A deep internal module with explicit same/different/unproven results;
preserve both ADRs and existing runtime behavior.

**Changes:** New `Sources/TidyCore/FilesystemIdentity.swift` and
`Tests/TidyCoreTests/FilesystemIdentityTests.swift`. No generic filesystem wrapper.

**Data structures:** RecordedIdentity, ExactObservation and IdentityVerdict.
Descriptor capture and live/recorded continuity verification own backend policy;
structural equality does not grant authority. Test-only observation injection must
not become a public bypass. Unknown/malformed evidence is unproven, not absent.

**Routing:** Internal-module implementation, using the phase-1 qualified contract.

**Static verification:** Swift checks/lint; private I/O adapter; explicit errors;
no time tolerance, hash/path fallback or new dependencies.

**Runtime verification:** Cover qualified capture, unsupported capture, same legacy
metadata with different injected incarnations, mixed proofs, and proof loss.
Use real descriptor integration for capture; synthetic incarnation collisions test
the policy seam and are not falsely called observed APFS inode reuse.
