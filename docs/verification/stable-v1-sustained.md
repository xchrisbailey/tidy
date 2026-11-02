# #15 — bounded repeated-workload resource observation

2026-11-02. **Passed 20 repeated-workload rounds on this host.** This is additional
resource evidence, not induced memory-pressure, leak-free, minimum-hardware or
aggregate stable-v1 qualification. Existing external gates and deferrals remain.

## Workload and isolation

```sh
env NSUnbufferedIO=YES bash scripts/model-smoke.sh --qualify-sustained
```

Added an explicit opt-in packaged diagnostic; ordinary app/task behavior is
unchanged. It uses the approved candidate revision
`50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b` through the existing local qualification
setup. The wrapper denies network and build-directory resource fallback. No new
download, personal-file operation, native permission change, system-wide memory
pressure tool or synthetic memory allocator was used.

On **Apple M4 Max, 36 GiB, macOS 27.0.1 (26A434)**, one process performed:

- Twenty 100-file metadata sorts: **2,000 completed moves**.
- Twenty 12-file content-naming batches: **240 completed renames**. Uses the first
  12 eligible fixtures from the unchanged versioned corpus; this is not another
  independent naming assessment or full mixed-codec corpus replay.
- Each batch required its exact expected change count, no failures/unprocessed
  files and byte-preserving undo through a newly constructed coordinator.
- Unload every fifth round, reloading the same approved artifact after rounds
  5, 10 and 15. This is not replacement between two production revisions.

Only generated temporary fixtures/bookmarks/journals were mutated; the diagnostic
cleans its own uniquely created root. All 11 approved-source weight hashes were
rechecked unchanged afterward. No installed-app data was used or cleared.

## Observations

| Measurement | Result |
| --- | --- |
| Rounds | **20/20**, all exact counts, original bytes and reopened undo passed |
| Workload elapsed | **353.265 s**, excluding initial verified load/build/package; includes three later reloads |
| Initial verified load | **1.996 s** |
| Round elapsed | **16.667–19.969 s** for metadata + content + their undos; not per-file generation latency |
| Post-round main-process physical footprint | **2,589,462,752–2,688,159,992 bytes** |
| OS-reported lifetime maximum main-process physical footprint | **4,688,498,768 bytes**, already present at the initial loaded observation |
| MLX-reported peak | **3,173,866,488 bytes**; a different metric, not total process memory |
| Main-actor heartbeat | **3,364 ticks**, maximum observed gap **0.1133595 s**; not native UI responsiveness evidence |
| Final post-unload observation | MLX active **16,232 bytes**, cache **0**; main-process physical footprint **750,800,280 bytes** |

Physical footprint rose by about 99 MB between the first and final post-round
observations, with steps across reload cohorts. Post-unload footprint did not
immediately return to zero; the final caller observation was lower than the
immediate round-20 unload observation. These facts do not identify a leak, prove
absence of leaks, or establish eventual reclamation. Do not replace those values
with a claim that unloading releases all process memory.

The existing `proc_pid_rusage` report now also records
`ri_lifetime_max_phys_footprint` and query status. All recorded queries returned
zero/success. The SDK's `sys/resource.h` exposes this field in `rusage_info_v4`.
It is an OS-accounted **main-process lifetime maximum**, not a sampled maximum or
the aggregate peak of the parser/XPC/process tree, GPU/system allocation, swap,
compressed memory, or the machine's total unified-memory demand. MLX accounting
must not be substituted for those missing measurements.

The run completed in about six minutes with no intentionally induced system
pressure. It cannot establish hours-long stability, recovery from actual pressure,
a hard resource bound, another Mac/macOS configuration or minimum supported RAM.
Likewise, the event-loop heartbeat says nothing about actual native interaction.

## Verification and evidence

Full debug and hosted optimized suites passed with the existing authorized iCloud
fixture and diagnostic identity opt-ins enabled, not skipped: **129 coordinator,
16 model, 2 worker and 18 workspace functions**. Lint and whitespace checks passed.
No production dependency or validation policy changed. The batch helper's optional
expected-count assertion tightens this opt-in run without changing previous callers.

Raw log: `.build/native-matrix/sustained-model.log`; parsed counts/memory samples:
`sustained-results.json`; full-suite logs: `sustained-debug-full.log` and
`sustained-optimized-full.log`. No per-round results were dropped or replaced.
Changes remain local/uncommitted; no commit, push, merge or release occurred.

The genuine pressure/minimum-hardware gate remains open, along with durable
volume-incarnation identity proof, TCC revocation, independent naming assessment,
production-version replacement, #16/#18 dispositions and the owner's formal
undo-cancellation/native-offline/diagnostic-export deferrals.
