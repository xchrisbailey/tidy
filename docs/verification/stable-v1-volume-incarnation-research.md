# #15 — volume-incarnation research

2026-11-02. **Decision: still BLOCKED.** No reviewed public contract establishes
restart-safe continuity across volume clone/restore/rollback using the available
ordinary-user, sandbox-compatible observations. Keep phase 2 and production
activation paused. This is a documentation gap in the proposed proof, not a
security-vulnerability finding or proof that macOS cannot provide such a facility.

## Scope and evidence boundary

Read the approved [overview](../../brain/plans/01-stable-filesystem-identity/overview.md),
[phase-1 gate](../../brain/plans/01-stable-filesystem-identity/phase-01-feasibility.md),
[feasibility evidence](stable-v1-identity-feasibility.md) and
[birth-time investigation](stable-v1-birthtime-investigation.md). Those local
observations remain unchanged: exact birth time can shift outside Tidy; qualified
APFS capability/UUID/full-ID capture, actual sandbox own-container capture and
read-only remount passed. None measured whole-volume clone/restore/rollback.

This follow-up read only Apple documentation/source and installed SDK headers/man
pages. No target code, probes, apps, mounts, permission changes or installations
were run. Apple’s APFS PDF was checked through indexed primary-source excerpts;
direct text fetching did not support its PDF content type. No claim below depends
on a third-party APFS implementation or on an inferred private ioctl.

## What the public contracts actually establish

| Candidate | Documented lifetime / meaning | Gate result |
| --- | --- | --- |
| Qualified full file ID | `VOL_CAP_FMT_PATH_FROM_ID` explicitly implies IDs are “persistent and not recycled” **on this file system**. `PERSISTENTOBJECTIDS` alone promises persistence through unmount/remount, not non-recycling. On 64-bit-ID volumes use `ATTR_CMN_FILEID`, not legacy `fsobj_id_t` fields. [S1] | Genuine within-filesystem guarantee, not a cross-incarnation namespace guarantee. Require both valid and supported capability masks, as already planned. |
| Filesystem UUID | `ATTR_VOL_UUID` returns the filesystem UUID; APFS stores `apfs_vol_uuid` in its on-disk superblock. Neither cited description promises a new UUID after every restore/rollback or an independent non-restorable generation. [S2, S3] | UUID + full ID remains a candidate, not an approved durable proof. |
| `statfs.f_fsid`, device/mount name | `statfs` describes a filesystem ID and mount metadata, not a persistent incarnation. XNU’s generic `vfs_getnewfsid` uses a wrapping `u_short` counter and checks collisions against currently mounted filesystems. This is implementation evidence against treating generic fsids as everlasting; it is **not** a claim that APFS necessarily uses that allocator. [S4, S5] | No documented reboot/remount/non-reuse guarantee suitable for durable identity. An observed mismatch can trigger refusal; equality cannot prove continuity. |
| Mount flags | `MNT_SNAPSHOT` means the mount is a snapshot; `MNT_LOCAL` means local storage. Mount flags can be updated without unmounting. [S4, S6] | Useful eligibility/denial inputs. A live restored volume need not be identified by the meaning “snapshot mount”; absence of that flag is not restore detection. |
| Media/disk UUID | Disk Arbitration exposes separate volume and media UUID keys. IOKit promises a persistent media UUID **if available**; `diskutil` says a media UUID may derive from a GPT partition UUID. Its APFS crypto “Disk UUID” also means the volume UUID, not a second physical witness. [S7, S8] | Do not confuse field names with independent provenance. Partition identity is not a restore epoch. |
| Hardware serial / physical attachment | IOKit defines a device product serial property, while an IOMedia “whole disk” can also be a virtual replica. Neither description is a filesystem-incarnation contract. [S7, S9] | Could reject some migrations, but same-device rollback remains unresolved. Sandbox availability and reliable descriptor-to-backing-device binding are unmeasured; additional access would not itself solve the contract. |
| Foundation IDs/bookmarks | Resource and volume identifiers are explicitly not persistent across system restarts. Bookmarks locate resources and security-scoped bookmarks preserve access; stale status requests bookmark renewal, not historical-object attestation. [S10] | Retain for access/location only. Successful or non-stale resolution is not documented clone/rollback exclusion. |

**Inference:** a non-recycling guarantee plus an independently guaranteed,
incarnation-distinguishing namespace would support the proposed normal-operation
proof. The reviewed sources provide the first ingredient, not the second. The
capability text does not explicitly define restore as a new filesystem incarnation
or say how an application recognizes one. Do not invent that interpretation in
either direction. Merely observing distinct IDs after file cloning does not answer
whole-volume namespace semantics.

## APFS transactions and generations do not currently supply the missing API

Apple’s format reference documents monotonically increasing, non-reused `xid_t`
transaction numbers. It also describes `apfs_next_obj_id`, `nx_next_oid`, container
and volume UUIDs, snapshot transaction references, and rollback fields. In
particular, mounting with nonzero `apfs_revert_to_xid` reverts to the selected
snapshot, deletes later snapshots/current state, and then **clears that field**.
Thus it is not a documented lasting “a rollback happened” flag. [S3]

These are **on-disk format descriptions**, not a documented ordinary-user
descriptor API for a persistent incarnation token. The reference names
`apfs_cloneinfo_id_epoch` and `apfs_cloneinfo_xid`; their names alone establish no
public callable API or lifetime guarantee. No qualifying volume-incarnation/XID
accessor was found in the reviewed public `sys/attr.h`, `statfs` surface or Apple
APFS API guide. This bounded search is not proof that none exists. XNU VFS source
does not establish the APFS driver's restore implementation. [S1, S3–S5, S11]

The public object generation count is different: `ATTR_CMN_GEN_COUNT` tracks data
modification, permits only equality comparisons for the **same** object, and can
return invalid zero for mmap'ed files. It is not a volume incarnation or permission
to infer identity from equal data. [S2, “ATTR_CMN_GEN_COUNT”]

The installed snapshot man page requires superuser privileges plus an entitlement
for all `fs_snapshot_*` functions, including listing. `diskutil listSnapshots`
documents current snapshots and their XIDs, not an immutable history of reverted
branches. The `asr` manual explicitly documents restore/replication and preservation
of snapshot name/UUID on the destination. Snapshot UUID is therefore not an
independent volume witness. None of these documents supplies the required
ordinary-user sandbox continuity API. [S8, S12, S13]

Even a readable current XID would need more than a monotonicity comparison:
normal writes advance it; an older image could subsequently advance beyond a
previously recorded value. Equality with an earlier transaction would reject
legitimate later writes. These are reasoning limits, not observed APFS test
results. There is no cited guarantee binding such comparisons to branch ancestry
or guaranteeing that an offline restored copy receives a fresh external epoch.

## Limits versus measurements

- **Conditional theoretical limit:** if a restore reproduces every stored and
  observable input to an identity decision, that decision cannot distinguish the
  restored history from the original. This is indistinguishability, not evidence
  that every Apple restore preserves every field. A witness outside the restored
  state, with a documented relevant lifetime, could change the premise.
- **Documented:** the within-filesystem no-recycle capability, UUID meanings,
  snapshot restore facilities, and descriptor lifetimes above. None explicitly
  supplies the required independent epoch.
- **Unmeasured / not promised:** exact UUID/ID/XID behavior of each restore tool,
  rollback path, reboot, duplicate-volume attachment and sandbox device lookup.
  More fixtures could falsify candidates and characterize tools, but finite passes
  cannot manufacture a missing lifetime contract. Missing evidence must remain
  `unproven`, not “ordinary user implies no restores.”

## Honest partial candidate: continuously retained live descriptors

`open/openat` returns a descriptor referring to the opened object; relative lookup
uses its directory descriptor. `unlink` delays removal of an open file until all
references close, and `close` documents per-process object references and their
release on process exit. Forced unmount makes later accesses to active ordinary
files fail even after remount. [S14]

This supports a **separately approved, live-operation-only design candidate**:
retain actual descriptors continuously from an initially validated capture; use
them as live authority, not a serialized descriptor number or a reopened pathname.
Retain every necessary authority role, preserve grants, no-follow/ancestor checks,
single-link restrictions, content-freshness checks and final entry binding. Fail
closed on descriptor errors, loss of access or lost live state; never turn a
reopened historical record into retained-descriptor proof. Pinning one file does
not attest unpinned ancestors, current contents or the current directory entry.

**Gate before even this partial change:** approve its separate scope; independently
review binding/race and filesystem-lifetime assumptions; then authorize bounded
integration qualification of metadata drift, replacement, descriptor closure and
invalidated access. No blanket protection against live filesystem reload/rollback
is established here. Do not use it to bypass uncertain mount state.

This does **not** meet the approved durable goal: a fresh process/crash recovery has
lost the references, older history cannot be backfilled, and retaining descriptors
has resource costs. It does not recover the stranded native task. Keep durable
`FileIdentity` and legacy refusal unchanged; this note authorizes no implementation.

## Smallest next decisions/resources

1. **Recommended now:** keep STOP, preserve strict exact-birth-time policy and
   record the existing undo limitation. No more identity stress loops are needed
   to reach this decision.
2. If pursuing the durable backend, obtain an Apple filesystem engineering/DTS
   clarification identifying a **public API and explicit lifetime contract**:
   namespace + full ID across supported clone/restore/rollback paths, ordinary-user
   App Sandbox access, reboot/remount behavior, and reliable ambiguity detection.
   A clarification must point to a usable supported contract, not just assert
   observed implementation behavior. Alternatively identify a supported independent
   local witness that demonstrably survives/detects those restore boundaries.
3. Only after that contract exists, request authorization for disposable-volume
   clone/restore/rollback/duplicate-namespace qualification and external-grant,
   minimum-OS/reboot qualification. This research does not request or perform those
   operations. If no such resource is available, the smallest owner decision is
   to retain the documented limit, or separately authorize guidance/live-descriptor
   exploration—not silently remove clone/restore from the existing promise.

Formal undo-cancellation, native-offline and diagnostic-export owner deferrals are
unchanged; none is reopened or completed here. #15 remains open.

## Primary sources

`SDK` below is the installed
`/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk`.
Header paths are relative to that exact SDK; host man-page paths are absolute.

- **S1:** `SDK/usr/include/sys/attr.h:142–146,212–240,490–510`;
  [Apple XNU counterpart](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/attr.h).
- **S2:** `SDK/usr/share/man/man2/getattrlist.2`, sections
  `ATTR_CMN_OBJID`, `ATTR_CMN_OBJPERMANENTID`, `ATTR_CMN_GEN_COUNT`,
  `ATTR_VOL_UUID`, volume capabilities. The installed header is authoritative for
  the full-width API choice where older man-page wording differs.
- **S3:** [Apple File System Reference](https://developer.apple.com/support/downloads/Apple-File-System-Reference.pdf),
  sections `oid_t`, `xid_t`, `nx_superblock_t`, `apfs_superblock_t`, especially
  `apfs_revert_to_xid`, `apfs_revert_to_sblock_oid`, `apfs_next_obj_id`, `apfs_vol_uuid`.
- **S4:** `SDK/usr/share/man/man2/statfs.2`; `SDK/usr/include/sys/mount.h:212–237`.
- **S5:** [Apple XNU `bsd/vfs/vfs_subr.c`](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/vfs/vfs_subr.c),
  `mntid_gen`, `vfs_getnewfsid` (source inspection, not a stable application ABI).
- **S6:** `SDK/usr/share/man/man2/mount.2`, `MNT_UPDATE`, `MNT_RELOAD`.
- **S7:** `SDK/System/Library/Frameworks/IOKit.framework/Versions/A/Headers/storage/IOMedia.h:147–165`;
  `SDK/System/Library/Frameworks/DiskArbitration.framework/Headers/DADisk.h:39–62`.
- **S8:** `/usr/share/man/man8/diskutil.8`, `unlockVolume`, crypto users,
  `listSnapshots`, “SPECIFYING DEVICES” UUID form (`:1430,1507,1612–1625,2415–2419`).
- **S9:** `SDK/System/Library/Frameworks/IOKit.framework/Versions/A/Headers/storage/IOStorageDeviceCharacteristics.h:149–175`.
- **S10:** `SDK/System/Library/Frameworks/Foundation.framework/Headers/NSURL.h:80–97,428–464,794–852`;
  [Apple bookmark guide](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/AccessingFilesandDirectories/AccessingFilesandDirectories.html#//apple_ref/doc/uid/TP40010672-CH3-SW10).
- **S11:** [Apple APFS Tools and APIs](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/APFS_Guide/ToolsandAPIs/ToolsandAPIs.html)
  (retired guide; not treated as an exhaustive current API inventory).
- **S12:** `SDK/usr/share/man/man2/fs_snapshot_create.2:47–87` (shared documentation
  for create/delete/list/rename/mount/revert).
- **S13:** `/usr/share/man/man8/asr.8:476–535`, “REPLICATION AND THE INVERTER” and
  “RESTORING WITH APFS SNAPSHOTS”.
- **S14:** `SDK/usr/share/man/man2/open.2:76–127`, `unlink.2:53–65`,
  `close.2:48–76`, `mount.2:139–153`.
