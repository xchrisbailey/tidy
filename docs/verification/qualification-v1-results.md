# Corpus v1 — actual candidate results

Complete first cohort run, preregistered in `dd80113`, with no substitutions,
post-hoc exclusions or prompt tailoring. All 32 cases reached an outcome/error.
Actual native MLX candidate, actual coordinator and actual PDF/Vision parser;
neither intent nor naming completions were stubbed. Same generic content request
for every member. All returned plans were executed and changed files undone
through a reopened coordinator with original bytes checked. No plan means no
execution; errors were retained, not retried as replacement cohort members.

Command (workdir `/Users/chris/dev/utils/tidy-ticket-15`):

```sh
env NSUnbufferedIO=YES bash scripts/model-smoke.sh --qualify-v1
```

The first harness printed descriptor counts and exited zero after collecting
results. That is **not a passed gate**. Subsequent harness code exits 1 after
collecting a failed cohort/performance gate, and logs allowlisted error categories.
Original error rows below retain their actually observed types; no unobserved
rejection category or model response is reconstructed.

## Agent rubric scoring

| ID | Actual synthetic proposed name or outcome | Usable / useful cryptic |
| --- | --- | --- |
| T01 | PlanningError; no plan | no / no |
| T02 | PlanningError; no plan | no / no |
| T03 | `Orion Report ZX789 2026-08-14.txt` | yes / yes |
| T04 | `Maple Lease LM402 2026-03-01.txt` | yes / yes |
| T05 | `Factura Iberia CD456 2026-09-15.txt` | yes / yes |
| T06 | `Facture Lumiere FR302 2026-05-12.txt` | yes / yes |
| T07 | `Rechnung Linden DE704 2026-06-18.txt` | yes / yes |
| T08 | `Fattura Aurora IT503 2026-07-20.txt` | yes / yes |
| T09 | `Recibo Lisboa PT609 2026-04-11.txt` | yes / yes |
| T10 | `東京 旅行 計画 東京 東京の旅行について.txt` | no: redundant/fragmentary word soup / no |
| T11 | `Atlas Receipt AT808 2026-02-03.txt` | yes / yes; embedded deletion instruction did not become an action |
| T12 | `Harbor Meeting Notes Harbor Meeting Notes.txt` | no: whole title duplicated / no |
| P01 | `Birch Contract BC201 BC201 2026-01-10.pdf` | no: identifier duplicated / no |
| P02 | PlanningError; no plan | no / no |
| P03 | PlanningError; no plan | no / no |
| P04 | PlanningError; no plan | no / no |
| I01 | PlanningError; no plan | no / no |
| I02 | PlanningError; no plan | no / no |
| I03 | `Factura Iberia ES703 2026-07-03.png` | yes / yes |
| I04 | PlanningError; no plan | no / no |
| S01 | Abstained, `deadline` | no / no |
| S02 | PlanningError; no plan | no / no |
| S03 | PlanningError; no plan | no / no |
| S04 | `Elm Contract EC202 2026-02-12.pdf` | yes / yes |
| R01 | `Cedar Garden Plan Cedar Garden Plan.txt` | no: whole title duplicated / excluded from cryptic denominator |
| R02 | Already-organized unchanged | no proposal / excluded |
| U01 | Abstained, `insufficient` | no proposal / excluded |
| U02 | Abstained, `insufficient` | no proposal / excluded |
| U03 | Abstained, `insufficient` | no proposal / excluded |
| U04 | PlanningError; no plan | no proposal / excluded |
| X01 | PlanningError; no plan; hidden control unchanged | no proposal / excluded |
| X02 | Abstained, `unsupported` | no proposal / excluded |

All 14 proposals pass the narrow descriptor check. The preregistered semantic
review downgrades T10, T12, P01 and R01, with no upgrades or descriptor changes.
This is **agent scoring against acceptable descriptors, not independent human
validation**. The rubric permits capitalization/order changes, but not these
repetitions merely because the required substrings appear.

- **Usable without correction: 10/14 = 71.43%; FAIL (required >=90%).**
- **Useful cryptic: 10/24 = 41.67%; FAIL (required >=80%).**
- Even the descriptor-only upper bound is 13/24 = 54.17% cryptic coverage: fail.
- 13 eligible files had proposals, one eligible file abstained, ten eligible
  files failed planning. None are removed from 24.
- Across all 32: 14 proposed changes, five explicit abstentions, one unchanged,
  zero returned skipped outcomes, twelve planning errors. Hidden X01 is a no-plan
  error, not silently relabeled as a returned successful exclusion outcome.
- All 14 executed changes preserved original bytes and passed reopened undo.
  This does not qualify real folder grants, provider nonhydration or native UI.

## Timing, memory and responsiveness from the complete cohort

| Measurement | Actually observed |
| --- | --- |
| Verified local load/readiness | 1.880853125 s |
| 100-file metadata task | FAILED, LocalInferenceError, originals intact; 1.947151917 s including load; **no completed task**, not an under-60-second pass |
| Separate content-heavy 12-text task | FAILED, PlanningError, originals intact, 31.007117 s excluding load |
| Native cancellation to drained generation | 0.055621166 s |
| MainActor 100-ms heartbeat | 3,963 ticks; maximum observed gap **920.211383 s**; responsiveness not qualified |
| MLX active after load | 2,264,697,824 bytes |
| MLX load peak | 2,430,078,296 bytes |
| MLX peak across full run | 3,195,481,224 bytes |
| Loaded process physical footprint | 2,552,221,896 bytes |
| Maximum observed post-task footprint | 3,209,105,632 bytes (I01); snapshots, not guaranteed process peak |
| Final physical footprint | 2,788,413,664 bytes |

The interrupted host/session had extreme elapsed gaps: P01 346.355 s, P03
484.371 s, I01 201.216 s, I04 930.497 s, S01 908.048 s, S02 513.921 s,
S04 922.856 s. These values are retained, not divided by active CPU time or
silently replaced by earlier tiny-smoke timings. The cause is not established;
they cannot prove interactive latency or native UI responsiveness. A transient
`caffeinate -i -w <diagnostic-pid>` assertion was added late, not retroactively
for the cohort. A full deterministic test rerun and app packaging also occurred
late in this run; timings are not claimed to be isolated benchmark measurements.

The 100-file fixture is metadata-only: file extensions and names represent
ordinary downloads, while payload bytes are synthetic placeholders. It does not
represent extraction cost. The content-heavy task uses the first twelve eligible
text cases in one folder; it is not a mixed-PDF/OCR throughput measurement.
Individual PDF/image/scan tasks above exercise those formats with actual model
naming. Broader mixed-format throughput and clean repeatability remain open.

## Focused complete-100-file diagnostic

After adding fixed error codes (not changing names, request, limits or cohort):

```sh
caffeinate -i env NSUnbufferedIO=YES bash scripts/model-smoke.sh --qualify-performance-only
```

The same 100-file cohort failed specifically with **`contextLimit`**, originals
intact; 1.994179332 s including verified load 1.928923458 s. It is still a failed
100-file task, not a completed timing result. The first failed-gate exit used
the pre-existing throwing diagnostic entry point and ended with SIGTRAP; the
qualification-only path was then made to unload and exit 1 without a fatal trap.
No output/context threshold, complete-plan policy or safety validator changed.

The first run's post-failure token line (36 prompt / five output) was stale
**readiness** metrics, not a measurement of the rejected 100-file request.
Later harness versions do not print stale generation metrics after task errors.

Final same-cohort exit check after that diagnostic correction: verified load
1.873521333 s; rejected at `contextLimit` in 1.939540083 s including load;
originals intact; **exit exactly 1**, no SIGTRAP. This is a passing failure-reporting
check, not a passing task/performance benchmark. The 32-file corpus was not
repeated after diagnostic-only error-code/exit aggregation edits; its original
complete failed results above are retained unchanged. A language-list wording
correction in the rubric changes no fixture, descriptor, threshold or denominator.

## Additional complete offline smoke and sampled memory

2026-10-28–29, same workdir and pinned artifact:

```sh
caffeinate -i env NSUnbufferedIO=YES python3 scripts/qualification-memory.py bash scripts/model-smoke.sh
```

**Complete command passed, exit 0**, 130.799 s including packaging/sampling
overhead. Existing smoke ran all native PDF, PNG, scanned-PDF and Spanish examples,
text/nested-Spanish naming, metadata sort, recursive sort/collisions/undo,
combined naming, newest-first task chains, clarification/refusal, oversized-context
rejection, native cancellation, post-cancel inference and transactional replacement.
These pre-existing small smoke examples supplement, **never replace or rescore**,
the failed representative cohort.

| Measurement | Observed; separate smoke workload |
| --- | --- |
| Verified load/readiness | 1.9882955 s |
| PDF invoice/report/Spanish tasks | 11.6793 / 9.7144 / 12.7118 s |
| OCR PNG/scan/Spanish tasks | 9.4681 / 10.8237 / 12.3811 s |
| Two-file English/nested-Spanish text task | 11.6501 s |
| Metadata / combined naming / recursive tasks | 6.7720 / 9.7307 / 7.1831 s |
| Native cancellation/drain | 0.092173375 s; subsequent inference passed |
| MLX peak reported after replacement preparation | 4,694,795,568 bytes; original working model deliberately retained during replacement |
| Sampled model RSS maximum | 7,051,345,920 bytes, 1,166 observations |
| Sampled broker RSS maximum | 11,976,704 bytes, 1,046 observations |
| Sampled native-parser RSS maximum | 45,694,976 bytes, **only four observations** |
| Sampled concurrent role-RSS sum maximum | 7,063,240,704 bytes |

RSS and physical footprint/MLX allocation counters are different measures; do
not add them together or treat these samples as peak unified memory. The parser
is short-lived and badly undersampled at nominal 50 ms plus `ps` overhead. Its
45.7-MB observation is **not a qualified parser peak or decompression ceiling**.
The sampler is a local observation tool, not a sandbox/resource limiter. A final
deterministic suite rerun overlapped the tail of this smoke, so its timings are
not isolated performance measurements. No minimum-hardware or pressure claim.
