# #15 — remaining qualification on the current host

2026-10-31. Based on merged `main` at `2c50de34`, on
`ticket/15-remaining-qualification`. **#15 remains open. No hardware is formally
qualified.** This follow-up adds bounded evidence and fixes one reproduced model
cleanup defect; it does not change the corpus, thresholds, model, dependencies,
release status or existing owner deferrals.

Host remains M4 Max / 36 GB / macOS 27.0.1. Earlier
[recovery](stable-v1-recovery.md) and
[installed-beta folder checks](stable-v1-native-permissions.md) remain evidence,
not checks that must be repeated.

## Reproduced defect and regression coverage

A real interrupted loopback URLSession download produced keyed-archive resume
metadata with `NSKeyedArchiveRootObjectKey`, rather than the plain dictionary
expected by cleanup. Explicit partial cleanup removed its resume record but left
the transfer's `CFNetworkDownload_…` temporary partial behind. The regression
failed before the production change and passed afterward.

Cleanup now accepts plain property lists and both archive root-key spellings,
using secure decoding restricted to Foundation data classes. Existing basename
and temporary-file prefix restrictions remain. Tests preserve unrelated data and
reject traversal names. Real-transfer tests inspect only their own partial,
verify its fixture bytes, then test explicit cleanup or temporary-file eviction
followed by a new consented transfer. Eviction is deliberately simulated by
deleting that owned temporary file, not by inducing system-wide cache eviction.

New child-process tests use production storage, selection and URLSession transfer
with two tiny fixture revisions and a controlled runtime. Actual SIGKILL occurs:

| Checkpoint | Fresh-process result |
| --- | --- |
| Replacement transfer after received bytes | Original verified revision ready; replacement partial retained. |
| Candidate loading, before selection commit | Original verified revision ready; verified candidate installed but not selected. |
| Selection committed, before load returns | Newly selected verified candidate ready. |

Restoration starts no transfer. Consented removal and a further fresh process
leave no installed/partial revision or readiness; unrelated storage survives.
Unconsented removal preserves selection and installed revisions. Ten repetitions
passed: **30 SIGKILL cases, 20 real partial-loss/cleanup cases, and 20
plain/archive safe-cleanup cases**. This is not termination during actual MLX
replacement or qualification of a second production model artifact.

## Disposable volume checks

A 256 MiB case-sensitive APFS sparse image was mounted at an owned worktree path,
not a personal volume. Distinct case-spelled files had independent inodes/bytes.

- All eight journal/move/undo SIGKILL checkpoints passed fresh-process recovery,
  repeated recovery without mutation, fixture-byte and canary checks. Explicit
  undo was checked where applicable, including empty created-folder cleanup.
- **37 existing metadata, mutation-safety and natural-language test functions**
  passed with `TIDY_TEST_FIXTURE_ROOT` on that filesystem. Ordinary runs retain
  their default temporary fixture location.
- The model's real storage check rejected setup before transfer/staging. Physical
  capacity was **268,394,496 bytes**, with **266,600,448 bytes free**, below the
  fixture's **536,870,921-byte** requirement. The production important-usage
  capacity API conservatively returned **0** on this image; physical free space
  was not zero. Network was denied and unrelated storage remained unchanged.
- With history outside the image, recovery after detaching the selected volume
  returned uncertain, kept durable history bytes, and did not mount or recreate
  the folder. Remount restored authority; explicit undo restored bytes and
  removed the empty created folder. The image was detached afterward.

This is bounded case-sensitive/removable-volume evidence, not power-loss,
every-filesystem, sandbox/TCC-revocation or disk-exhaustion-during-mutation proof.

## Isolated native controls and scope

The development bundle was copied to **Tidy Qualification**, ad-hoc signed with
the existing entitlements and a unique bundle ID/container. Approved local weights
were APFS-cloned with distinct inodes, not downloaded or hardlinked. All 11 source
model hashes were recorded and rechecked unchanged. Installed Tidy data was not
used. These observations are not final signed/notarized distribution checks.

| Native action | Observed and independently verified result |
| --- | --- |
| Restore cloned model; sort owned fixture | Ready; real-model task completed; file hashes preserved. |
| Clear History → Cancel | Exact journal bytes and both completed records retained. |
| Confirm Clear History and Lose Undo | No retained history; only recovery records removed. Model, grants, sorted files and unrelated canaries retained. |
| Remove active model → Cancel | Ready/Active and selection retained; all 11 clone hashes unchanged. |
| Confirm Remove Model | Readiness withdrawn; clone and selection removed, unrelated storage/grants/fixture bytes preserved. |
| Relaunch after both destructive controls | Setup Required; task submission replaced by setup; History empty; selected-folder grant restored. |
| Submit owned 1,001-file scope | Explicit 1,000-file/safe-traversal-limit refusal; exact 1,001 filenames/bytes unchanged; no sorting folder or history created. |
| Default Sort by type | Only direct-child `top.txt` moved; nested/hidden files and existing folders preserved. Native 1-of-1 undo restored paths/hashes and removed empty `Documents`. |
| Sort by type including subfolders | Both `top.txt` and `Nested/nested.txt` moved to root `Documents`; hidden subtree and `Nested/KeepFolder/.keep` unchanged. Native 2-of-2 undo restored exact file set, paths and hashes; existing folders preserved. |

Automation limitations are retained: the 1,001-item picker exceeded Accessibility
tree budgets; its default Grant was activated after owned-path navigation and the
main path/count independently checked before submission. Accessibility set-value
changed displayed request text without committing the SwiftUI binding; that
attempt repeated the default direct-child task and was undone. Physical text
entry plus focus change submitted the intended recursive request successfully.
Neither an action-success envelope nor an uncommitted display value was counted
as a passing recursive task.

After intentional history loss, the first controls fixture was restored manually,
not through app undo. Recursive fixtures were restored through native undo. The
second model clone was removed through native confirmation; No installed model
was observed. Both canaries and source hashes survived. The app was closed and
only its temporary LaunchServices registration removed; evidence/container retained.

## Local verification and resource observations

All passed locally:

```sh
swift test --disable-automatic-resolution
bash scripts/release-tests.sh
bash scripts/lint.sh
git diff --check
bash scripts/build-app.sh
caffeinate -i env NSUnbufferedIO=YES python3 scripts/qualification-memory.py bash scripts/model-smoke.sh
caffeinate -i env NSUnbufferedIO=YES bash scripts/inspection-smoke.sh --fixture-workers
```

Debug and hosted optimized runs reported **124 coordinator, 16 model, 2 worker,
18 workspace functions**. The real-provider test was explicitly skipped; the
optimized harness checked all 124 discovered coordinator functions reported.
Before PR publication on 2026-11-01, the complete debug suite, lint and diff
whitespace checks passed again; the real-provider fixture remained skipped.
Packaged model smoke ran with network denied. Parser containment and fixture
workers passed hang, cancellation/reap, oversize, crash, malformed and bad-text
checks, including denied file read, persistent write and network access.

Verified model load/readiness took **3.039 s**. Sampled RSS maxima were model
**7,034,683,392**, parser **44,630,016**, broker **11,976,704 bytes**; parser had
only four observations. MLX reported peak **4,694,863,152 bytes**. The sampled run
took **72.868 s including packaging**, not a task benchmark. RSS sampling is not
true peak/unified memory, a hard bound, sustained memory pressure or minimum-Mac
qualification. Existing naming/performance results were not rescored here.

Local raw evidence: `.build/remaining-qualification/volume-check/{results,capacity,unavailable-results}.json`
and `native-profile/{native-controls-results,native-scope-results,recursive-baseline,source-model-baseline}.json`.
Logs under the session's approved temporary directory use prefix
`tidy-remaining-`, including `debug`, `optimized`, `model-repeat`,
`case-sensitive`, `native-memory`, `inspection` and the pre-fix `cleanup-red-final`.
Ignored local artifacts are not published repository evidence by themselves;
this document records the bounded outcomes and committed tests provide repeatable
model coverage.

## Remaining gates and required prerequisites

| Gate | Disposition |
| --- | --- |
| Real-provider cloud-only nonhydration, recursive/refresh/relaunch coverage | Unverified; requires separately authorized disposable provider fixtures. Ordinary files and marker flags do not substitute. |
| Sandbox/TCC revocation and recovery | Unverified; POSIX denial and detached-volume recovery do not substitute. |
| Independent naming assessment and broader real-world formats/languages | Unverified; requires independent human scoring and representative authorized inputs. Existing fixed-corpus scores remain agent-scored. |
| Minimum Mac/macOS, sustained pressure, hard parser/IPC/I/O resource bounds | Unverified; requires other configurations and dedicated resource/stress evidence. No supported-hardware claim. |
| Genuine production-revision replacement/MLX interruption/pressure | Unverified; no second reviewed production revision exists. Fixture process tests and same-artifact clones do not substitute. |
| Remaining native clarification/confirmation/cancellation/disclosure/privacy/error matrix | Partial earlier evidence only; these scope/control checks do not complete the whole matrix. |
| Formal undo-cancellation, native-offline, diagnostic-export reruns | Existing owner deferrals unchanged; not silently passed or reinstated. |
| Accessibility and final distribution/clean-user installation | Track #18 and #16 and existing owner dispositions; not established by this isolated development identity. |

No CI, release, global permission changes, new provider locations or model download
was introduced. Aggregate issue checkboxes must not be marked complete from this
bounded follow-up.
