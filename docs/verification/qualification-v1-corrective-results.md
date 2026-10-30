# #15 corrective qualification — unchanged corpus

2026-10-29. Started clean at `41bde97`, also the integration tip. The user explicitly
reopened naming reliability and task/context architecture, **not thresholds or
benchmark scope**. Final measured code: `7373eb31f31453730d39602410afb5bd4817d873`.
Earlier failed [baseline](qualification-v1-results.md) remains unchanged.

**Final agent-scored naming gates PASS: 21/22 usable proposals = 95.45% (>=90%),
21/24 useful cryptic files = 87.50% (>=80%).** All 32 original cases were run.
The representative 100-file task completed all 100 operations in **6.46154 s**,
including verified loading; the separate content-heavy 12-text task completed all
12 changes in **9.63572 s**, excluding loading. Both passed bytes/reopened undo.

**This is not release approval. Supported hardware: NONE qualified.** Independent
human scoring, native GUI/grants/provider checks, minimum hardware/OS, pressure and
real-world corpus qualification remain open. Tested host only: M4 Max, 36 GB,
macOS 27.0.1. Neither macOS 14 nor 16-GB hardware was tested.

## Fixed inputs, runtime and commands

The [preregistered rubric](qualification-v1-rubric.md), manifest, denominators,
requests, threshold values and model artifact were **not changed**. No new
dependencies, model downloads, cloud fallback, CI, personal sync-file access or
primary user-documentation edits.

| Input | SHA-256 |
| --- | --- |
| `QualificationCorpus.json` | `1c119f14c51362c0d35c3926c72c8baf64211f11eb322984e4b134e71e35e148` |
| Rubric at corrective baseline and final tree | `4d1fef5ff9153171d34ad768f510e3fd05bda78f33b19f530184c24eb428e905` |
| `Package.resolved` | `82b8add2a7946a24ef8dd3a4dc21675beb5dbe2cf8ff1bf7fbfc355ccaaafce8` |

Candidate: `mlx-community/Qwen3-4B-Instruct-2507-4bit`, immutable revision
`50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b`, existing approved artifact in
`~/Library/Application Support/Tidy/QualificationModels`, 2,278,969,697 verified
allowlisted bytes. Native MLX Swift LM 3.32.3, MLX Swift 0.32.3, Transformers
1.3.5; exact revisions and redistribution/provenance limitations remain as recorded
in [ticket-6.md](ticket-6.md). Candidate Apache-2.0; roots MIT/MIT/Apache-2.0;
existing locked transitive notices unchanged. Swift 6.4 / Xcode 27.1 on Mac16,6,
14-core M4 Max / 36 GB / macOS 27.0.1 (26A434), same host as the baseline.

Workdir for every command: `/Users/chris/dev/utils/tidy-ticket-15`.

```sh
swift test --disable-automatic-resolution
bash scripts/lint.sh
git diff --check
caffeinate -i env NSUnbufferedIO=YES bash scripts/model-smoke.sh --qualify-v1
caffeinate -i env NSUnbufferedIO=YES python3 scripts/qualification-memory.py bash scripts/model-smoke.sh
caffeinate -i env NSUnbufferedIO=YES bash scripts/inspection-smoke.sh --fixture-workers
bash scripts/build-app.sh
git merge --no-edit integration/tidy-v1
```

Each complete qualification cohort ran in the foreground with `caffeinate`, with
**no concurrent agent builds, tests, model runs, memory sampler or pressure work**.
Packaging/build and fixture creation are outside measured task time. Model loading
includes whole-artifact verification and readiness generation; no download. This
is not cold-boot/cache-flush evidence. The signed native diagnostic denies network
and original build-product reads and verifies effective loopback denial. The
separate sampled smoke is not used as the 100-file timing benchmark.

## Causes and corrective architecture

1. **Inventory repetition exhausted context.** Reproduced unchanged full100 at
   `contextLimit` in 2.02859 s including load, originals intact. The coordinator
   regression exposed an 8,119-byte input before system instructions. Intent now
   interprets only the bounded request into the same validated rule program.
   `files: "all"` means deterministic expansion over **every captured candidate**,
   not a wildcard filesystem path or permission to discover new files. Legacy
   per-source arrays still require exact, unique, complete source coverage.
2. **Title and filename reconstruction duplicated information and created copy
   errors.** The model now selects a zero-based heading index where suitable
   source headings exist. At most 16 complete, filename-safe lines are candidates,
   each 8–160 UTF-8 bytes and 2–12 word components. Full retained evidence remains
   available; no long line is truncated into a candidate or reported as complete
   evidence. Without candidates, the grounded source-word title path remains.
   Selected headings are bound to the inspected source ID and copied exactly.
3. **Preservation belongs to deterministic assembly.** The app adds only missing
   original words, numeric tokens and proper-name tokens, with the exact extension,
   then runs grounding, preservation, language and whole-plan checks. It does not
   repair an invalid model-supplied legacy filename. Explicit null filenames,
   unknown fields, invalid/invented IDs and invalid heading indices are rejected.
   Unsupported requested translations abstain; only the existing grounded
   six-language document-descriptor vocabulary may translate descriptors.
4. **Unicode numeric classification created Japanese word soup.** `京` has a
   numeric value even inside ordinary place names. `Character.isNumber` caused
   unrelated Japanese prose to become mandatory identifier material. Preservation
   now uses Unicode Number categories Nd/Nl/No, not written numeric words in the
   Letter category. Arabic-Indic identifiers, Roman-number literals, dates and
   original names remain protected, with coordinator regressions.
5. **Confident OCR errors are not trustworthy IDs.** OCR can fuse an identifier
   directly with an ISO-like date. Such ambiguous OCR evidence now abstains rather
   than splitting or repairing it. This is a general source-kind/token-boundary
   check, not an ID/descriptor blacklist. Both affected corpus files remain in the
   24-file denominator. It can conservatively abstain on a genuinely fused literal.
6. **Generic intent feedback failed to repair combined requests.** The complete
   native smoke exposed two rejected rename-evidence responses. Fixed-category
   feedback now distinguishes clause/evidence binding, case, separators and exact
   quoted literals. The same request then passed its one allowed replacement.
   Validation conditions, literal case/whitespace and authorization were not relaxed.

The native 8,192 combined-token bound, 2,048 output ceiling, 512 naming budget,
inspection bytes/pages/pixels/deadlines and **one task-wide invalid replacement**
are unchanged. No chunks, prefix plans or partial execution are introduced.
All metadata expansion and all content decisions finish before global collision
reservation and the first mutation. Actual snapshots, captured ancestor authority,
exclusive moves, >100 confirmation/counts, 1,000-candidate limit, cancellation,
progress, durable recovery and newest-first undo remain authoritative.

The old smoke assumption that 303 long names must overflow context is obsolete,
not a safety gate removed to pass: its replacement verifies a **complete 303-file
native plan**, 302 changes plus one abstention, with confirmation blocking all
mutation. A separate actual-native oversized input still fails at the unchanged
context limit without prefix acceptance.

## Coordinator red → green and retained failures

All new regressions use the agreed public coordinator seam, real temporary files,
observable plans/results, actual native OCR where applicable, and controlled
completion replies only for deterministic validation/state cases. Actual candidate
benchmarks below never substitute controlled completions.

Observed failing commands used `swift test --disable-automatic-resolution --filter`
with these exact test names, then passed after their individual changes:

- `compactIntentExpandsEveryCapturedFileBeforeAnyMutation`: oversized input and
  invalid compact response → complete 100-file plan, execution and reopened undo.
- `groundedTitleExpandsProtectedTokensOnceWithoutFilenameReconstruction`:
  invalidResponse → grounded title plus exact name/ID/date/extension once.
- `groundedTitleAssemblyUsesOnlyAuthorizedDescriptorTranslation`: invalidResponse
  → bounded grounded translation.
- `redundantGeneratedHeadingRequiresOneReplacementBeforeAnyMutation`: duplicated
  title accepted → rejection, one complete replacement, no earlier mutation.
- `fusedOCRIdentifierAndDateAbstainsInsteadOfGuessingBoundaries`: real OCR reached
  naming and proposed a fused identifier/date → insufficient-evidence abstention.
- `compactNamingCannotTreatInvalidNameAsOmittedOrResetReplacementBudget`: null
  filename accepted → rejection after the shared intent replacement was consumed.
- `titleAssemblyAbstainsWhenRequestedTranslationHasNoGroundedVocabulary`:
  untranslated unsupported title accepted → explicit insufficient abstention.
- `headingSelectionIsBoundedAndExpandedWithoutRetypingEvidence`: invalidResponse
  → bounded index rejection/replacement, bytes and reopened undo.
- `writtenNumeralInsideJapanesePlaceNameDoesNotBecomeAnIdentifier`:
  invalidResponse on ordinary Japanese evidence → clean source heading.

Additional characterization covers compact 1,000/1,001 scope, 101 confirmation and
partial cancellation, recursive global reservations/undo, and non-ASCII numeric
preservation. Existing malformed legacy envelopes, authority, race, retention,
inspection, model lifecycle and recovery tests remain. Temporary `[DEBUG-q15]`
category/boolean probes were removed; no raw prompts/completions or real names
were logged. No unsupported fork/syscall workaround or journal-lock change remains.

Failed empirical attempts are retained separately, not averaged into or replaced
by the final cohort:

| Run | Usable/proposed; useful/24 | Full100 / content12 |
| --- | --- | --- |
| Original `41bde97` baseline | 10/14 (71.43%); 10/24 (41.67%) | contextLimit / planning failure |
| Early corrective working tree, before `87b7ca3` | 19/23 (82.61%); 19/24 (79.17%); I03 planning error | 6.77634 s complete / invalidResponse 7.80343 s |
| `87b7ca3` | 20/23 (86.96%); 19/24 (79.17%) | 6.57669 s complete / invalidResponse 9.50022 s |
| `e191460` | 20/22 (90.91%); 20/24 (83.33%); Japanese prose still redundant | 6.71203 s complete / 9.58123 s complete |
| `33649fe` | 21/22 (95.45%); 21/24 (87.50%) | 6.40668 s complete / 9.97283 s complete |
| `427812b` | same 21/22; 21/24 | 6.44524 s complete / 9.58664 s complete |
| Final `7373eb3` | same 21/22; 21/24 | 6.46154 s complete / 9.63572 s complete |

The first corrective full native smoke failed during combined naming after earlier
successes; its sampler recorded exit -5. Focused `--metadata-evidence-only` runs
reproduced that rejection before precise feedback fixed it. Those failed runs
remain failures. One early full parallel deterministic run also reported an
unlocalized `.busy` in the unchanged recovery conflict test; the focused test and
subsequent complete suites passed. A proposed fork-based probe did not compile in
Swift and was removed. Its cause is **not claimed diagnosed or fixed**; concurrency
repeatability remains an investigation risk, not permission to retry mutations.

## Final complete 32-case results at `7373eb3`

All cases retain original IDs and eligibility. Times include per-file planning,
execution and reopened undo; token pairs are the **last successful completion**,
not task totals. A dash in the name column means no proposal. Agent semantic
review made no upgrades or extra downgrades in this final run: S03 fails the fixed
descriptor rubric because native OCR read `Factura` as `Faclura`.

| ID | Actual synthetic resulting name / outcome | Usable | Seconds | Last prompt/output tokens |
| --- | --- | --- | ---: | ---: |
| T01 | `Acme Invoice AB123 2026-10-28.txt` | yes | 2.90177 | 306/20 |
| T02 | `Cedar Garden Plan.md` | yes | 2.85982 | 282/20 |
| T03 | `Orion Report ZX789 2026-08-14.txt` | yes | 2.89499 | 307/20 |
| T04 | `Maple Lease LM402 2026-03-01.txt` | yes | 2.89729 | 311/20 |
| T05 | `Factura Iberia CD456 2026-09-15.txt` | yes | 2.89213 | 318/20 |
| T06 | `Facture Lumiere FR302 2026-05-12.txt` | yes | 2.90163 | 319/20 |
| T07 | `Rechnung Linden DE704 2026-06-18.txt` | yes | 2.91425 | 327/20 |
| T08 | `Fattura Aurora IT503 2026-07-20.txt` | yes | 2.91692 | 326/20 |
| T09 | `Recibo Lisboa PT609 2026-04-11.txt` | yes | 2.89686 | 319/20 |
| T10 | `東京 旅行 計画.txt` | yes | 2.92242 | 335/20 |
| T11 | `Atlas Receipt AT808 2026-02-03.txt`; embedded instruction not acted on | yes | 3.01838 | 331/20 |
| T12 | `Harbor Meeting Notes.txt` | yes | 2.91685 | 284/20 |
| P01 | `Birch Contract BC201 2026-01-10.pdf` | yes | 3.10409 | 338/20 |
| P02 | `Nova Report NR404 2026-04-22.pdf` | yes | 3.08941 | 328/20 |
| P03 | `Factura Sol ES602 2026-06-02.pdf` | yes | 3.12896 | 343/20 |
| P04 | `Willow Letter WL107 2026-02-19.pdf` | yes | 3.12367 | 331/20 |
| I01 | — abstained, `insufficient`, fused OCR ID/date | no proposal | 2.57991 | 1533/78 (intent) |
| I02 | `Orbit Receipt OR205 2026-05-04.png` | yes | 3.22171 | 327/20 |
| I03 | `Factura Iberia ES703 2026-07-03.png` | yes | 3.23116 | 339/20 |
| I04 | `Meadow Event Schedule.png` | yes | 3.20510 | 305/20 |
| S01 | — abstained, `insufficient`, fused OCR ID/date | no proposal | 2.59676 | 1533/78 (intent) |
| S02 | `Lake Report LR508 2026-05-08.pdf` | yes | 3.23649 | 327/20 |
| S03 | `Faclura Luna ES809 2026-08-09.pdf` | **NO** | 3.25040 | 338/20 |
| S04 | `Elm Contract EC202 2026-02-12.pdf` | yes | 3.23791 | 329/20 |
| R01 | — already-organized unchanged | excluded | 2.95587 | 282/20 |
| R02 | — already-organized unchanged | excluded | 3.10335 | 310/20 |
| U01 | — `insufficient` abstention | excluded | 2.40698 | 1533/78 (intent) |
| U02 | — `insufficient` abstention | excluded | 2.58312 | 1533/78 (intent) |
| U03 | — `insufficient` abstention | excluded | 2.57849 | 1533/78 (intent) |
| U04 | — `unreadable` abstention | excluded | 2.46350 | 1533/78 (intent) |
| X01 | — hidden control skipped | excluded | 2.39273 | 1533/78 (intent) |
| X02 | — `unsupported` abstention | excluded | 2.39733 | 1533/78 (intent) |

Totals: **22 proposals, seven explicit abstentions, two unchanged, one skipped,
zero errors**. The two eligible abstentions stay in 24. All 22 executed names,
including unusable S03, passed original-byte checks and reopened undo. S03 is
not fixed by guessing/correcting a descriptor. This is **agent scoring**, not
independent human validation, and threshold passage is not universal accuracy.

## Final timing, memory and responsiveness

| Measurement | Final cohort observation |
| --- | --- |
| Verified load/readiness | 1.851780750 s; included measured load span 1.851867584 s |
| Full100 | 100 planned/changed, zero abstained/failed; **6.461541251 s including load**; 1529/106 intent tokens, 1.13919 s prefill / 2.64107 s generation |
| Content-heavy12 | 12 planned/changed, zero abstained/failed; **9.635715875 s**, load excluded; last naming completion 338/21 tokens |
| Native cancel to drained work | 0.002536250 s; a point measurement, not an upper bound |
| MainActor 100-ms heartbeat | 1018 ticks, maximum gap 0.110166167 s; not native UI evidence |
| MLX active after load | 2,264,697,824 bytes |
| MLX peak across cohort | 3,173,264,512 bytes |
| Loaded physical footprint | 2,563,231,992 bytes |
| Largest post-task footprint snapshot | 3,017,937,144 bytes (I01); not proven process peak |
| Final physical footprint | 2,591,002,872 bytes |

The separate complete native smoke passed at the same code, exit 0, **65.785 s**
including packaging/sampler overhead. It covered native PDF/OCR/text/languages,
metadata/task chains, combined rules, recursive reservations/undo, actual 303-file
confirmation, unchanged hard context rejection, model replacement, cancellation
and post-cancel inference. Its cancellation measurement was 0.011639875 s.
Sampled model RSS reached **7,054,753,792 bytes** (606 observations), broker
11,976,704 bytes (521), parser 34,406,400 bytes (**only three observations**),
concurrent sampled sum 7,066,664,960 bytes. MLX replacement peak was 4,694,792,496
bytes while retaining the working model. RSS, MLX allocations and physical
footprint are different measures; do not sum them. The prior ~7-GB observation
has **not** become a proven peak or a 16-GB compatibility claim. Short-lived native
parsers are undersampled; pressure/internal-decompression ceilings remain open.

## Final checks and remaining gates

- Complete local suite passed: **115 non-skipped functions** (103 reported core
  including one provider skip, 11 model and two supervisor functions), with
  parameterized safety cases. Earlier failures are retained above.
- Strict lint, five plists, shell syntax, `git diff --check`, packaged native
  inspection/controlled-worker containment and cleanup, and arm64 app packaging /
  inside-out ad-hoc signatures passed. No native GUI was launched or claimed.
- Integration merge reported already up to date at `41bde97` before final evidence.
- No model/context/inspection budget increased; no threshold, denominator,
  descriptor, request, corpus member, fixture byte generator or language priority
  was adjusted to obtain these scores.
- Still open: independent human scoring; real degraded/handwritten/mixed-script
  scans and general unstructured content; confident OCR errors such as S03;
  minimum hardware/macOS 14/16 GB; memory pressure/parser true peak; unlocalized
  early recovery `.busy`; actual process/power-loss recovery; real grants and
  revocation; real provider nonhydration; native setup/task/history/storage/
  accessibility/cancel smoke; clean-user/final distribution qualification.

The corpus remains short, synthetic and heading-rich. Indexed extraction is
intentionally generic, not a hardcoded list of expected benchmark titles, but
its success here cannot establish representative real-user quality. Do not close
#15 or advertise any supported Mac until the remaining gates are actually met.
