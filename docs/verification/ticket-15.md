# #15 — local qualification, not release approval

## Corrective follow-up, 2026-10-29

The user explicitly authorized fixing naming reliability and complete-plan context
architecture while retaining the corpus, rubric, requests, thresholds and model.
The final unchanged 32-case run now passes agent-scored naming gates:
**21/22 usable proposals (95.45%)**, **21/24 useful cryptic files (87.50%)**.
The complete 100-file task finished in **6.46154 s including verified loading**;
the separate 12-text task finished all 12 changes in **9.63572 s** excluding load.
All passed original-byte checks and reopened undo. One OCR-derived proposed name
remains unusable and two eligible OCR files abstained; neither is hidden from the
denominators. See [complete corrective evidence](qualification-v1-corrective-results.md)
for the architecture, red/green tests, all failed intermediate runs, complete
per-case results, memory/response measurements and latest checks.

**#15 remains open. Supported hardware remains NONE qualified.** Passing these
synthetic agent-scored benchmarks does not complete native/manual, independent
human, real-provider, recovery-repeatability, minimum-hardware or release gates.
The original failed baseline below is retained as historical evidence, not the
latest naming/performance result.

2026-10-28–29. Work started clean on `ticket/15-qualification` at requested
`2c10efd8f82ebcc60f40faea8acc3b1b6c2c2bce` (`integration/tidy-v1`).
**Keep #15 open. Supported hardware: NONE qualified.** The tested machine below
is not a supported-hardware declaration; required human/environment gates remain.

## Reproduction and fixed inputs

The naming corpus and rubric were committed **before inference** in `dd80113`.
See [qualification-v1-rubric.md](qualification-v1-rubric.md) for composition,
denominators, scoring and limitations. Corpus SHA-256:
`1c119f14c51362c0d35c3926c72c8baf64211f11eb322984e4b134e71e35e148`.
`Package.resolved` SHA-256:
`82b8add2a7946a24ef8dd3a4dc21675beb5dbe2cf8ff1bf7fbfc355ccaaafce8`.

**Actual first complete cohort: 10/14 proposed names usable (71.43% <90%),
10/24 eligible cryptic files useful (41.67% <80%): both naming gates FAIL.**
The unchanged 100-file cohort also fails at the native context bound, with zero
mutations; a quick rejection is not a completed under-60-second task. The
separate 12-text content-heavy task failed planning. Full per-file outputs,
agent semantic downgrades, abstention/error counts and observed latency/memory
are in [qualification-v1-results.md](qualification-v1-results.md).

These failures require explicitly revisiting model/prompt reliability and task
scope/context architecture; they do not authorize changing thresholds, dropping
hard files, claiming minimum hardware, silently reducing task scope or bypassing
complete-plan validation. No product or validator was modified to obtain a pass.

```sh
swift test --disable-automatic-resolution
bash scripts/lint.sh
git diff --check
bash scripts/build-app.sh
env NSUnbufferedIO=YES bash scripts/inspection-smoke.sh --fixture-workers
env NSUnbufferedIO=YES bash scripts/model-smoke.sh --qualify-v1
env NSUnbufferedIO=YES bash scripts/model-smoke.sh
```

Additional actual commands isolate the original full-100-file error and sample
process memory during the existing complete native smoke, respectively:

```sh
caffeinate -i env NSUnbufferedIO=YES bash scripts/model-smoke.sh --qualify-performance-only
caffeinate -i env NSUnbufferedIO=YES python3 scripts/qualification-memory.py bash scripts/model-smoke.sh
```

`caffeinate` holds a transient idle-sleep assertion only while its child runs;
it changes no persistent setting. It does not retroactively repair the first
cohort's interrupted latency evidence. The memory sampler uses only Python's
standard library and the system `ps`; no dependency is installed.

All commands run locally from this worktree. The first `swift test` allowed
resolution of the already-approved pinned graph; no new dependency or lockfile
change. No approval blocker, model download, cloud fallback, CI or remote pipeline.
No personal sync files or provider fixtures were inspected. Native synthetic
generation uses the existing CoreGraphics/CoreText helpers, not a new PDF library.
The signed diagnostic bundles package the native inspection XPC broker/parser
and MLX resources; inference runs with network access and original build-product
reads denied. A loopback `EPERM` probe verifies the effective network restriction.
Downloads/build/fixture generation are outside task timing; verified model loading
is included in the 100-file measurement. Reopened coordinator undo is not an
actual app-process/UI restart.

## Candidate, license and tested configuration

- Apple M4 Max, 14 CPU cores, 36 GB unified memory, MacBook Pro `Mac16,6`.
- macOS **27.0.1 (26A434)**, Xcode **27.1 (27A9275)**, Apple Swift
  **6.4 (swiftlang-6.4.0.34.1)**, arm64.
- Existing approved weights outside the repo:
  `~/Library/Application Support/Tidy/QualificationModels`.
- `mlx-community/Qwen3-4B-Instruct-2507-4bit`, revision
  `50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b`, 2,278,969,697 allowlisted bytes,
  verified through the normal model lifecycle before native inference.
- MLX Swift LM 3.32.3 (`3b339ad6e3b3f44c8121ecff5131c7fd55e075e6`), MLX Swift
  0.32.3 (`19601207e9a0de51e03ee6ec0c3c5f3784275075`), Transformers 1.3.5
  (`48473106a93b2d8dfb114b82f0628ebbb71734e7`). Existing greedy decoding,
  8,192 combined context and 2,048 output limits unchanged.
- Candidate/upstream Apache-2.0; runtime roots MIT/MIT/Apache-2.0, complete locked
  transitive notices in `Packaging/Notices`. Conversion card does not pin the
  upstream conversion revision or prove reproducibility. See
  [ticket-6.md](ticket-6.md) for artifact/license review, provenance limitations
  and dependency graph. This work neither changes redistribution terms nor
  substitutes ad-hoc signing for distribution approval.

## Open human/environment gates

- Real NSOpenPanel read/write grants, restoration/revocation, sandboxed consent,
  actual app-process restarts and final signed/notarized distribution behavior.
- Real File Provider cloud-only nonhydration: the opt-in test remains skipped;
  temporary files/marker flags are not proof. Do not run it against personal sync
  files without a separately authorized disposable provider fixture.
- Native GUI setup/download/storage, folder selection, clarification/resubmission,
  101-file confirmation/counts, progress/cancel availability, results explanations,
  task/file undo, History, keyboard/VoiceOver and visual responsiveness.
- Clean-user install/setup and real offline tasks after setup in the final app;
  the diagnostic's offline coordinator tasks supplement, not replace, these.
- macOS 14, 16-GB/lower-memory hardware, memory pressure, representative degraded
  photos/scans/handwriting, broader scripts, independent human naming scoring,
  native-parser internal peak memory and hostile-parser stress.
- Actual power loss/kill at durable mutation boundaries; deterministic injected
  interruptions verify recovery logic, not power-loss durability in every volume.

There is no evidence for qualifying macOS 14 or 16 GB from this M4 Max run. No
minimum supported Mac is established. Existing inspection limits remain provisional
resource policies, not qualified hard process-memory or wall-time guarantees.

## Deterministic evidence and inspection policies

The initial complete `swift test` passed 11 model lifecycle/transfer functions,
two real-worker supervisor functions and 92 reported coordinator functions with
one real-provider skip: **104 non-skipped functions**, including parameterized
cases. This covers real temporary files, native PDF/Vision extraction, persistent
undo/recovery, invalid plans, stale sources, collision reservations, cancellation,
scope, format limits and privacy canaries. There is no new application behavior
or product fix in this ticket; the already-approved public coordinator/runtime
and packaged inspection seams are reused. Controlled-model safety tests are not
counted toward empirical naming quality.

Inspection policies are retained without adjustment:

| Resource | Existing bound; qualification interpretation |
| --- | --- |
| Text input | Strict UTF-8 TXT/MD, 16,384 bytes/file, 65,536/task; reject oversize, not a prefix. |
| PDF/image compressed input | 20 MiB/file, 40 MiB/task shared; at most a rejection sentinel byte. |
| Evidence | 16,384 UTF-8 bytes/file, 65,536/task shared across formats; reject, never silently truncate. |
| PDF pages | First three, native text preferred, OCR only on empty native-text pages; encrypted/protected inputs abstain. |
| Images | PNG/JPEG/HEIC/HEIF/single-image TIFF; actual type/extension family checked; each side <=16,384, <=40 million source pixels. |
| OCR render | Longest side <=2,048, <=4,194,304 pixels; PDF RGBX allocation <=16 MiB excluding framework copies. |
| OCR policy | Vision revision 3 fast CPU recognition, automatic language detection, no language correction; all returned top-candidate confidences >=0.5. Not calibrated semantic accuracy. |
| IPC | <=100,000 actual reply bytes; serial independent killable parser; broker acknowledges reap. |
| Time | Cooperative one-second source-read/preflight clock; three-second parser supervision within five cumulative inspection seconds; 45-second content stage including naming. These are not hard wall-time bounds on OS/source I/O. |
| Model | <=8,192 combined tokens, <=2,048 output; naming requests <=512 tokens; one task-wide replacement allowance. No chunking, prefix acceptance or budget increase. |

See [ticket-10.md](ticket-10.md) and [ticket-11.md](ticket-11.md) for detailed
authority, containment and bound tests. Compressed bytes do not bound native
framework internal expansion. Real process peak/unified-memory pressure and
kill/scheduling/I/O latency remain unqualified. The memory sampler records only
this worktree's diagnostic roles at nominal 50-ms intervals; RSS samples can miss
short-lived peaks and double-count shared pages. It is not a memory limiter.

Content-retention evidence comes from coordinator/history and explicit-diagnostic
canaries in the complete suite; raw prompts, replies, document excerpts and
extracted text are not added to production logs/history. The qualification harness
prints only fixed categories/counters/timings and **synthetic ordinary resulting
filenames**, not raw completions. OS swap/logs/crash diagnostics and secure erasure
are outside this guarantee. Offline network denial verifies these task runs, not
every untested GUI/setup path or a universal absence of OS traffic.

## Local verification status

| Command/check | Result |
| --- | --- |
| Initial `swift test` | PASS, 104 non-skipped functions; one provider skip. |
| `swift test --disable-automatic-resolution` after harness work | PASS, same 104 non-skipped functions and provider skip. |
| `bash scripts/lint.sh` | PASS strict Swift format, all five plists, shell syntax. |
| `git diff --check` | PASS. |
| Python memory sampler AST parse | PASS; no third-party imports. |
| `bash scripts/build-app.sh` | PASS arm64 build, bundled resources, inside-out ad-hoc signing/deep strict verification; app not launched. |
| `caffeinate -i env NSUnbufferedIO=YES bash scripts/inspection-smoke.sh --fixture-workers` | PASS native PDF/PNG/scan naming/bytes/reopened undo under App Sandbox; all seven controlled worker cases, effective read/write/network denials, cleanup/reap and observed-parser abrupt-client-exit cleanup. |
| First complete `--qualify-v1` corpus | COMPLETE but FAILED qualification: both naming gates, metadata100, content-heavy12 and responsiveness; details linked above. |
| Exact full-100-file focused repeat | FAIL `contextLimit`, originals intact; no reduced cohort. |
| Focused failure-reporting red → green | Original top-level failure trapped; qualification-only entry now unloads and exits exactly 1. Same 100-file `contextLimit` failure remains, final 1.93954 s including 1.87352 s load. |
| Complete native offline smoke with memory sampler | PASS complete command, exit 0; 130.799 s including packaging/sampler overhead. Native content/metadata/recursive/task-chain/undo, replacement, context rejection, cancellation and subsequent inference all passed; not a replacement for the failed corpus. |
| Final `swift test --disable-automatic-resolution` after diagnostic edits | PASS, 104 non-skipped functions; one real-provider skip. |
| Integration merge | `git merge --no-edit integration/tidy-v1`: already up to date at `2c10efd`. |

An upstream MLX resource-bundle “missing creator for mutated node” warning remains
nonfatal. Successful deterministic containment tests do not convert failed model
quality/performance measurements into a release pass. No issue was closed.

Separate complete-smoke sampled model RSS reached 7,051,345,920 bytes; native
parser RSS reached 45,694,976 bytes in only four samples. These are not true peaks
or hard memory ceilings, and RSS differs from the cohort's physical-footprint
and MLX counters. Details and all caveats are retained in the linked results.
