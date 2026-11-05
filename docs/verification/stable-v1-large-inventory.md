# #15 — bounded large-inventory qualification

2026-11-04, merged base `60e299d`, branch
`ticket/15-lifecycle-resource-qualification`. Tested on the existing
M4 Max / 36 GB / macOS 27.0.1 host. No production behavior, task limit, model,
corpus or permission policy changed. **This is not aggregate #15 completion.**

## Executable workspace checks

```sh
env TIDY_LARGE_INVENTORY_TESTS=1 \
  swift test --disable-automatic-resolution --filter LargeInventoryTests
```

The opt-in suite creates 10,000 ordinary synthetic text files, a hidden file and
a folder containing one nested control. It uses the real workspace/coordinator
inventory path, with model readiness and completion controlled at the existing
test seam. Direct-child inventory must report 10,000 candidates and two skipped
items. Submitting the oversized task must refuse with `scopeTooLarge` before
model inference; no task result or undo history may appear. Every original file's
bytes and the direct-child count are checked afterward.

A separate refresh requests cancellation 10 ms after scheduling, requiring that
the workspace still reports `inspecting`. It verifies cancellation feedback,
cleared inventory, blocked stale submission, retained request/bookmark bytes,
empty history and a successful subsequent explicit refresh. It does **not** prove
which internal filesystem call was executing when cancellation was requested.

A cooperative main-actor heartbeat samples every 5 ms during initial inventory.
It must run more than twice; timings below are observations, not test thresholds
or native frame/input latency measurements.

| Run | Inventory elapsed | Heartbeat ticks / maximum gap | Cancellation drain |
| --- | --- | --- | --- |
| Initial focused debug | 0.635 s | 102 / 6.31 ms | 3.46 ms |
| Focused debug repeat | 0.675 s | 107 / 6.33 ms | 4.29 ms |
| Full debug | 0.666 s | 107 / 6.32 ms | 4.01 ms |
| Full optimized workspace | 1.078 s | 17 / 202.44 ms | 3.88 ms |

The optimized workspace pipeline runs other
workspace suites concurrently; its larger observed heartbeat gap is retained,
not discarded or attributed to a proven cause. These checks do not establish a
uniform responsiveness guarantee or a hard I/O cancellation deadline.

## Isolated native app

The existing signed isolated app/container was used, with no installed model
clone and no download. The retained native fixture contains the same inventory
shape, with zero-padded names through `item-09999.txt`.

- Selected the exact owned folder through the native read-only picker; verified
  its full path, read-only status and `10,000 eligible files · 2 skipped`.
- Physically typed `item-09999` into the filter and observed `item-09999.txt`;
  full-folder counts remained unchanged.
- Native Refresh preserved the filter/counts; How Tidy Works opened a popover,
  dismissed with Escape.
- Confirmed initial process 88698 exited; new process 90475 restored the exact
  folder/counts with Setup Required, without model setup.
- Verified all 10,002 file paths/hashes, byte-identical pre-existing history and
  unrelated container canaries afterward. Both app processes exited gracefully;
  only the temporary test registration was removed. Fixture/grants were retained.

The picker AXPress timed out although its modal opened; a fresh snapshot confirmed
state before continuing rather than clicking again. Its large accessibility tree
was truncated; Go To used the exact owned path and Return completed selection,
with main-window path/count verification afterward. An initial harness assertion
expected `10000`, not the displayed `10,000`; this was corrected as a harness
failure, not a product defect. Neither limitation was hidden as a clean attempt.

Native checks establish these completed interactions and restoration, **not**
native in-flight inventory cancellation or sustained UI/input latency. Existing
native partial-task cancellation remains historical evidence; formal undo
cancellation, native offline and diagnostic export remain owner-deferred.

## Full verification and boundaries

Full debug and hosted optimized pipelines passed with
`TIDY_LARGE_INVENTORY_TESTS=1`, the existing real-provider/identity opt-ins and the
approved small disposable volume enabled:

- 130 coordinator functions in 17 suites, including actual ENOSPC execution/undo;
- 16 model, two worker and **20 workspace functions in five suites**;
- lint passed. The disposable image was detached after both pipelines.

Afterward all 11 approved-source model hashes still matched the prior baseline.
Both real cloud-only controls retained the dataless flag using metadata-only
checks; no placeholder contents were opened. Python syntax and diff whitespace
checks passed as well.

Both full runs observed actual ENOSPC journal refusal in each variant and passed
fresh recovery/retry/undo. These are additional observations; the test still
correctly accepts durable success if APFS reclaims capacity between writes.

Retained local evidence under `.build/native-matrix/`:
`large-inventory-{initial,repeat,debug-full,optimized-full}.log`,
`large-inventory-native-profile.json`, `large-native-results.json`, native
snapshots and `large-inventory-history-before.json`. The profile records the
isolated app executable hash and exact fixture path.

This adds local metadata-inventory coverage, not slow/provider-filesystem latency,
minimum hardware/macOS, pressure qualification or independent naming assessment.
The existing provider tests separately verify real placeholder nonhydration;
they are not a large cloud-folder performance benchmark. Remaining prerequisites
and owner deferrals in [lifecycle/resource qualification](stable-v1-lifecycle-resource.md)
are unchanged. No CI, merge or release occurred.
