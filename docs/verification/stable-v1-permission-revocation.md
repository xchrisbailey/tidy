# #15 — permission revocation attempt and separate undo refusal

2026-11-01. Source `dc5ea7ee94b58db5882baf3435002f38f514c4f3`, branch
`ticket/15-permission-revocation`. **Revocation remains BLOCKED/unverified.** No
permission was changed. This attempt does not establish TCC or sandbox revocation,
and #15 remains open with no formally qualified hardware.

## Scope and preparation

The owner explicitly authorized a disposable `~/Documents/Tidy Qualification`
fixture and changes only to the isolated test app's permissions in System
Settings. A fresh `run-3ed61e26b1c848faa160ca52d352023f` child contained synthetic
`notes.txt`, `receipt.txt` and `.hidden-check`; initial hashes were recorded.
No personal files were opened or used for a task.

The current app was rebuilt and copied to **Tidy Permission Test**, with a unique
bundle ID/container, the production sandbox entitlements and ad-hoc signing.
Deep strict signature verification passed. Executable SHA-256:
`d88690482363c8132dff704221933ec11a5a65ffafb028494dd0490050de9bdb`.
Host: M4 Max / 36 GB / macOS 27.0.1. `agent-desktop` 1.0.2 operated the native UI.

The already approved model's 11 files were APFS-cloned into this new sandbox,
with independent inodes, not hardlinked/downloaded. Unrelated model-storage and
user-data canaries were placed in that container. Installed Tidy data and
permissions were not used or changed.

## Baseline and blocked permission control

1. The isolated app verified/loaded the cloned model and showed Ready.
2. Its native write picker selected the exact owned Documents fixture. The main
   window showed that path, two eligible files, one skipped and write access.
3. Native Sort by type completed both moves. Independent checks verified both
   destination hashes, the unchanged hidden file and exactly two completed
   journal entries. History showed **2 recorded changes · 0 undone** for the
   exact fixture path.
4. Opened **System Settings → Privacy & Security → Files & Folders**. The pane
   showed its application-permission list. A complete, untruncated exact heading
   search found **zero Tidy Permission Test entries**. No corresponding switch
   was available to change in that observed pane.

The user-selected-folder sandbox grant worked, but this observation does not
establish that it has a revocable TCC Documents switch. It also does not prove
that every macOS version/configuration lacks a suitable mechanism. A supported,
scoped method still needs to be established for this app identity/access path.

No broad or per-app TCC reset, database edit, other app's setting, modified
entitlement, deleted bookmark or POSIX denial was substituted. Neither a denied
operation nor regrant/recovery after actual revocation was tested.

## Separate finding: normal undo refused after birth-time metadata drift

During cleanup, before any permission change, native Undo Task stopped:

> The recorded file or folder cannot be identified safely. Tidy stopped; check
> undo history before trying again. … 0 of 2 recorded files undone.

History showed Needs attention, disabled undo, and the uncertain-identity
explanation. A native action-success envelope was not counted as successful undo;
an independent original-path check also failed because both files remained sorted.

Exact `stat` comparison against the durable journal established:

| Identity | Recorded vs current |
| --- | --- |
| Selected root | Device, inode, birth seconds and nanoseconds all match. |
| Both files | Device, inode, birth seconds and nanoseconds all match; original bytes preserved. |
| Created `Documents` sorting folder | Same device/inode and birth seconds; **birth nanoseconds changed from `616944000` to `616944074`**. |

The strict folder-identity comparison therefore rejects this observation. No
operation was resumed, no reversal occurred, and the journal's exact bytes were
unchanged. This is a fail-closed result, **not a successful ordinary undo or a
permission-denial pass**. The source of the 74-nanosecond metadata change is not
established; do not attribute it to iCloud, TCC, inode replacement or serialization
without a controlled reproduction. This single observation is not a repeatability
claim. No identity check was relaxed to force a pass.

Follow-up should reproduce the folder birth-time change with tightly scoped
before/after observations, distinguish provider/filesystem changes from capture
or persistence defects, and retain replacement-safety regressions before proposing
any identity-policy change. User-visible recovery guidance may also need review
if legitimate metadata drift leaves a task without app-assisted undo.

The subsequent [birth-time investigation](stable-v1-birthtime-investigation.md)
reproduces drift with raw POSIX mkdir/lstat and no Tidy journal, records its exact
floating-point conversion signature and adds deterministic fail-closed tests.
The writer remains unattributed; no identity tolerance or production fix is claimed.

## Cleanup and evidence

The isolated model was removed through its native confirmation. A fresh Settings
snapshot showed No installed model, and independent inspection found only the
storage canary. The app was closed and only its temporary LaunchServices
registration removed. All approved-source model hashes and both canaries matched
their baselines; the unique container and evidence remain retained.

Because native undo refused, the **synthetic fixture was restored manually, not
through app undo**: verified the exact owned sorted file set and original hashes,
moved only those two files back to unoccupied original names, removed only the
empty sorting folder, and rechecked the complete original file set/hashes. The
durable completed records were preserved, not rewritten or cleared to claim undo.
No permission or global sync setting was changed. System Settings was left open
on Files & Folders; no unrelated controls were operated.

Local evidence under `.build/permission-revocation/` includes `profile.json`,
`fixture-baseline.json`, `source-model-baseline.json`, `results.json`,
`pending-undo-snapshot.json`, `settings-test-app-search.json`,
`undo-refused-snapshot.json`, `undo-refusal-investigation.json`,
`exact-identity-comparison.log` and `model-removed-snapshot.json`. The app build
log is `tidy-permission-build.log` in the session's approved temporary directory.
Ignored artifacts alone are not published evidence; this document preserves the
bounded observations and distinguishes blocked, failed and restored states.

Only documentation changes resulted from this initial attempt. The production app built
successfully; lint and diff checks passed. No source/test behavior, dependency,
CI, release, qualification checkbox or owner deferral changed. Full suites were
not rerun for this documentation-only follow-up.
