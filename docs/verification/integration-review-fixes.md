# Integration review fixes

2026-10-29. Phase 1: `cf67c2e`; Phase 2 implementation: `b650507`, starting at
recovery integration `364a4f1`. Findings are from the pinned
`736cc24...7f3fee4` integration review. The checks below ran against the finalized
source tree subsequently committed as `b650507`; only this evidence was added
afterward. Hosted build metadata retains the precommit HEAD and dirty-source list.
The recovery [descriptor/lock-lifetime fixes](qualification-v1-recovery-safety.md)
remain intact. No busy retry, relaxed assertion, global serialization, dependency
change, model download, CI/cloud task or issue closure was introduced.

**Public release remains blocked; supported hardware: NONE qualified.** These
checks do not qualify native GUI grants, provider behavior, minimum OS/hardware,
pressure behavior or independent human scoring. The previous signed development
candidate predates these fixes and is stale. A final rebuilt Developer ID
unqualified candidate is separate work; no public release was produced here.

## Findings and implementation

1. **Dropped explicit selection:** Phase 1 binds recognizable extension and quoted
   name-substring restrictions independently of optional model fields, before
   inspection or plan expansion. Recognizable exact-file selection fails closed
   and requires clarification: the existing substring schema cannot express exact
   file identity. Controlled omitted-selection responses previously exposed an
   unrelated text marker to inference; replacement/rejection now prevents that.
2. **Case-only rename:** exclude only the exact source directory entry from its
   own occupancy calculation, not every matching case variant. Reuse the atomic
   exclusive rename; an existing destination is allowed only when it is the same
   ordinary single-link source identity in the same parent and the proposed name
   differs only in case. No overwrite primitive or temporary staging name is used.
   Journal the known destination-directory identity before the first checkpoint.
   Recovery inspects exact directory-entry spelling when both path lookups alias
   the same file, and offers undo for that self-alias rather than a false conflict.
3. **History cancellation/progress:** Phase 1 retains the undo task, exposes Cancel
   outside disabled controls and cancels on disappearance. Phase 2 reports initial
   and per-file checked/recorded-undone counts from the existing task-wide loop.
   The active-task flag and one journal lock cover every callback suspension,
   including the final callback and error paths. Cancellation stops subsequent
   reversals; completed reversals are retained, not rolled back. The observable
   history lifecycle drives determinate accessible progress and refreshes actual
   partial outcomes after completion, cancellation or failure.
4. **Passive model setup:** Phase 1 skips passive restore of an already-ready
   runtime, including repeated/concurrent window lifecycle calls. A new setup
   lifecycle still verifies installed files offline; explicit replacement/removal
   semantics remain covered and unchanged.
5. **Two mutation engines:** the synchronous one-file API constructs a planned
   change and delegates to the batch engine's `apply`, preserving its one-file
   requirement, occupied-destination error, legacy task identity/optional fields,
   thrown checkpoint errors and durable records. Both entry points now share the
   final root-path and ancestor/source identity checks and exclusive mutation.
6. **Two collision allocators:** one deterministic allocator owns case-folded
   occupied/allocated/reserved handling and stable numeric suffixes; callers keep
   filesystem and filename-limit validation. Original proposals remain reserved
   so a suffixed collision cannot steal another file's unsuffixed proposal.
7. **Divergent state wording:** Phase 1 shares one rename/move-neutral mapping
   between both history displays.

Exact-name recovery also exposed a directory-stream lifetime issue: `dup` shares
the directory offset, so reconciliation's first enumeration exhausted the second
inspection used to produce its report. Open `.` relative to the pinned directory
with an independent open description instead. The journal lock constructor and
explicit unlock-before-close destructor from recovery integration were not changed.

## Regression evidence

Agreed seams: public coordinator plus real temporary files, observable history
and model lifecycle with a controlled runtime. No tests of private helpers or
claims of native GUI automation.

- Before consolidation, 49 tests in five mutation/history/metadata/recovery suites
  passed. The same 49 passed after sharing `apply`, then again after extracting
  allocation. Existing failure injection/recovery coverage was retained.
- Red: case-only lowercase/uppercase/title-case plans produced unnecessary suffixes.
  Green: exact spelling, preserved bytes and reopened undo at both direct and
  recursive locations on this host's actual case-insensitive volume. A native
  probe confirmed alternate-case lookup resolves the source and `RENAME_EXCL`
  returns success while changing the stored spelling.
- Red: interrupted case-only records could not be classified accurately. Green:
  intent/before-move/after-move/undo-intent/after-undo-move checkpoints reconcile
  exact names without resuming changes. Unrelated replacements before execution,
  at the mutation boundary and during undo are preserved; the original identity
  remains intact at its deliberately parked test location.
- Red: root replacement at the final boundary still mutated the relocated root.
  Green: both the one-file and batch entry points stop without moving its file or
  modifying the unrelated replacement root. Existing recursive ancestor-swap
  coverage remains enabled.
- Red: the new undo progress seam emitted nothing and did not cancel after one
  recorded reversal. Green: callbacks report `[0, 1]` checked/undone before
  cancellation, retain one changed file, then permit explicit completion through
  a reopened coordinator. Same- and cross-coordinator operations get `.busy`
  throughout callbacks, including full completion. The observable history test
  also verifies live counts and cancellation's durable partial outcome.
- One initial full-debug run exposed an old recursive regression's expectation of
  the buggy case-only `(2)` suffix. That fixture now uses a non-case-only prefix
  as well as lowercasing to retain its meaningful occupied-original undo conflict.
  Separate direct/recursive exact-case tests cover the intended corrected result.
  The failure was not suppressed or accepted as success.

Temporary logs are under the approved OpenCode temporary directory, named
`phase2-baseline.log`, `phase2-engine-migration.log`,
`phase2-allocator-migration.log`, `phase2-case-red.log`,
`phase2-case-recovery-red.log`, `phase2-case-recovery-green.log`,
`phase2-case-conflicts.log`, `phase2-progress-red.log`,
`phase2-progress-green.log`, `phase2-root-red.log`,
`phase2-debug-full.log` (initial failure), and `phase2-debug-full-final.log`.

## Checks

Workdir: `/Users/chris/dev/utils/tidy-review-fixes`.

```sh
swift test --disable-automatic-resolution
caffeinate -i swift test --disable-automatic-resolution --maximum-repetitions 10 --repeat-until fail
bash scripts/release-tests.sh
caffeinate -i env NSUnbufferedIO=YES bash scripts/model-smoke.sh --qualify-v1
caffeinate -i env NSUnbufferedIO=YES bash scripts/model-smoke.sh
caffeinate -i env NSUnbufferedIO=YES bash scripts/inspection-smoke.sh --fixture-workers
bash scripts/build-app.sh
codesign --verify --deep --strict --verbose=2 .build/Tidy.app
bash scripts/lint.sh
git diff --check
```

Full debug: PASS, 113 core tests/14 suites, 12 model tests/two suites and two
inspection-supervisor tests. Parameterized cases are additional to these reported
test-function counts. Strict Swift formatting, plist/shell lint and whitespace
checks pass.

Ten-repeat full-debug safety run: PASS, 113 core tests/14 suites (142.980 s),
12 model tests/two suites (13.707 s), two inspection tests (4.071 s). Repetition
counts are per test, not ten fresh processes. No failure or unexpected busy result
was retried/accepted. Log: `phase2-debug-repeat10.log`.

`scripts/release-tests.sh`: PASS. Proper optimized Developer ID hardened-runtime
test host, copied production XPC/parser and serial hosted core suite: **all 113
discovered core test functions** passed (29.218 s). Normal optimized model suite:
12 tests (1.356 s); inspection supervisor: two tests (0.486 s). Host retained at
`.build/release-tests/host.q6Gbx5`, including discovery comparison, signatures and
build provenance. Log: `phase2-optimized-hosted.log`. This is not production App
Sandbox picker-grant evidence or a final distributable candidate.

Offline actual-model smoke: PASS, using the existing verified Qwen candidate
artifact, no download. Network and reads of original build-product resources were
denied by the wrapper; the copied Metal library was used. Real native PDF/OCR/text
naming, languages, protected tokens, metadata+rename/sort chains, recursive
collisions, byte preservation/reopened undo, the complete 303-file confirmation
case, hard-context rejection, failed/cancelled replacement, generation cancellation
and post-cancellation/replacement inference all passed. Log:
`phase2-offline-model-smoke.log`. No real user files or provider folders were used.

Packaged inspection fixture-workers: PASS, including real PDF/PNG/scan operations,
hang, cancellation acknowledgment, oversize, crash, malformed/bad-text output,
parser-profile denial of file reads/persistent writes/network connections, and
abrupt-parent-exit cleanup. Log: `phase2-inspection-containment.log`.

Sandboxed arm64 developer app build and deep/strict signature verification: PASS.
This app and native diagnostics are **ad-hoc signed**, not the final Developer ID
unqualified candidate. Inspected entitlements retain App Sandbox, app-scope
bookmarks, user-selected read/write and network client for consented model setup.
Package audit found copied Metal resources, notices and the independent XPC
broker/parser in their expected locations; no escaping links, model weights or
credential-key artifacts. Log: `phase2-app-build.log`. GUI launch/grants were not
tested.

### Unchanged native corpus and performance rerun

The 32-fixture manifest, rubric, requests, model and thresholds are unchanged.
All native cohorts ran in the foreground under `caffeinate`, **without concurrent
builds/tests/model jobs or memory sampling**. Existing model:
`mlx-community/Qwen3-4B-Instruct-2507-4bit` revision
`50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b`, 2,278,969,697 verified allowlisted
bytes under `~/Library/Application Support/Tidy/QualificationModels`. Host remains
the M4 Max/36-GB/macOS 27.0.1 development machine, not qualified minimum hardware.

| Fixed input | SHA-256 |
| --- | --- |
| Corpus | `1c119f14c51362c0d35c3926c72c8baf64211f11eb322984e4b134e71e35e148` |
| Rubric | `4d1fef5ff9153171d34ad768f510e3fd05bda78f33b19f530184c24eb428e905` |
| Package.resolved | `82b8add2a7946a24ef8dd3a4dc21675beb5dbe2cf8ff1bf7fbfc355ccaaafce8` |

Current rerun, not copied earlier-tip timing:

| Measurement | Result |
| --- | --- |
| All 32 naming fixtures | 22 proposals, seven abstentions, two unchanged, one skipped, zero errors; bytes/reopened undo pass |
| Agent rubric usable/proposed | 21/22 = 95.45%, passes >=90% |
| Agent rubric useful/cryptic eligible | 21/24 = 87.50%, passes >=80%; both eligible abstentions remain in denominator |
| Complete metadata100 | 100 planned/changed, zero abstained/failed; **7.883864958 s including verified load**, bytes/reopened undo pass |
| Included verified load span | 2.998537167 s |
| Content-heavy12 | 12 planned/changed, zero abstained/failed; **9.547551209 s excluding load**, bytes/reopened undo pass |
| Native cancellation to drained work | 0.006717667 s, point observation, not an upper bound |
| MainActor heartbeat | 1,046 ticks, maximum gap 0.110134125 s; not native GUI evidence |

Agent semantic review of all actual proposals against the unchanged required
descriptors found no additional downgrades and made no upgrades. T01–T12,
P01–P04, I02–I04, S02 and S04 are usable. I01/S01 abstain on insufficient OCR.
S03 remains **unusable** (`Faclura Luna ES809 2026-08-09.pdf`, OCR mistranscription
of `Factura`); no guessed correction or denominator change. R01/R02 stay unchanged,
U01–U04 abstain, X01 is skipped and X02 abstains unsupported. This is agent
scoring, **not independent human validation**. Log: `phase2-qualification.log`.
Prior qualification reports and their failures were not edited; prior memory
sampling/pressure limits are not newly measured or cleared by this run.

## Manual and release gaps

GUI unavailable: manually verify Cancel remains enabled/accessibly reachable while
undo controls are disabled; progress and partial outcomes in the history window;
closing the window during undo; and multiple setup windows during native inference.
Observable lifecycle/coordinator tests do not replace these native UI checks.
This host's case-insensitive volume is exercised; no separate case-sensitive-volume
or minimum-OS run is claimed. No independent human corpus scoring, native folder
grant/provider qualification, notarization/name/legal clearance or supported
hardware qualification is implied.
