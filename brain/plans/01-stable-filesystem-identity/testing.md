# Evidence gates and primary sources

Back to [[plans/01-stable-filesystem-identity/overview]].

## Primary-source basis, not hardware qualification

Read-only research used the installed macOS 27 SDK. Availability declarations and
older Apple source corroborate the candidate interfaces, but macOS 14 runtime
behavior and sandbox feasibility have **not** been qualified.

- Apple [XNU sys/attr.h](https://github.com/apple-oss-distributions/xnu/blob/xnu-10002.1.13/bsd/sys/attr.h):
  `VOL_CAP_FMT_PATH_FROM_ID` promises persistent/non-recycled object IDs;
  `PERSISTENTOBJECTIDS` alone promises remount persistence. Check valid masks.
- Installed `sys/attr.h`, lines 227–240: full-width `ATTR_CMN_FILEID` is the valid
  ID on 64-bit-ID volumes; document IDs and write generation counts are not
  object-incarnation proof.
- Installed `stat(2)`, `getfh(2)` and `fhopen(2)`: privileged generation/handle
  facilities are not an ordinary sandboxed-app solution.
- Installed Foundation `NSURL.h`, lines 428–431: file/volume resource identifiers
  are not persistent across system restart. Lines 603–604 document a persistent
  volume UUID when available, not an authenticated volume-incarnation token.
- Installed `clonefile(2)` and `copyfile(3)`: extended attributes can copy/clone;
  user-authored markers and signed-marker replay cannot prove unique incarnation.

Installed SDK prefix:
`/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk`.
These references establish design constraints, not a currently qualified backend.

## Call-site inventory for activation review

Identity capture currently spans `OperationJournal.swift` (ScopedDirectory,
pinFile, snapshots), `TaskCoordinator.swift` (inventory root/files),
`RecursiveScope.swift` (ancestors), `BatchOperations.swift` (plans/mutation), and
`MetadataPlanExpansion.swift` (destinations).

Authority comparisons also occur in `SortOperations.swift` (grants/undo/cleanup),
`NaturalLanguagePlanning.swift`, `ContentNaming.swift`, `ContentInspection.swift`,
`CaseOnlyRename.swift` and `Recovery.swift` (including newerOperation). Inventory
all comparisons again during implementation; this list is not a permanent proof
that new call sites cannot appear. Exact content snapshots must remain separate.

Existing replacements/symlink/race tests in SortAndUndoTests, MutationSafetyTests,
RecursiveScopeTests, ContentNamingTests and RecoveryTests remain mandatory. They
do not currently deterministically prove recycled-inode safety. Introduce a
narrow proof-observation seam to test distinct incarnations with identical legacy
tuples, plus real lifecycle tests corroborating the documented backend guarantee.

## Qualification matrix

| Property | Required evidence |
| --- | --- |
| Durable continuity | Real descriptor capture, documented non-recycling capability, valid persistent namespace, same-worker fresh process. |
| Metadata rewrite tolerance | Real filesystem metadata rewrite; successful undo only with qualified strong proof, legacy/unsupported refusal remains. |
| Replacement rejection | Root/ancestor/destination/file replacement, identical bytes, copied timestamps/markers and injected legacy tuple collision. |
| Authorization/freshness | Read/write grants distinct, revoked access refused, stale inputs rejected, later same-object edits retained by undo. |
| Ordering | Newer operations still block older undo across rewrites and mixed proof versions. |
| Durable safety | All eight actual SIGKILL checkpoints, atomic schema transition, unknown proof and old-binary downgrade refusal. |
| Namespace lifetime | Authorized remount/restart and clone/restore/rollback analysis; ambiguous namespace disables proof, never guesses. |

## Execution and reporting

Use existing local toolchain/dependencies and disposable, authorized fixtures only.
Implementation should invoke `tdd` and `diagnosing-bugs`; a focused security review
must state remaining namespace/race limitations rather than imply a full audit.
When a skill's execution isolation cannot be satisfied, record that validation
blocker instead of running a weaker check and calling it equivalent.

Full local verification: `swift test --disable-automatic-resolution`,
`bash scripts/release-tests.sh`, `bash scripts/lint.sh`, `git diff --check`.
Provider opt-in and actual native-app checks require separate evidence. No CI,
reboot, remote verification, production task or final-app permission change follows
automatically from approving this design.

Planning itself ran no new app/tests, capability probes or filesystem mutations.
Earlier uncommitted diagnostic tests and verification evidence are preserved.
