# #15 — actual activation interruption and disk exhaustion

2026-11-03. Based on merged `main` at `60e299d`, on
`ticket/15-lifecycle-resource-qualification`. The owner authorized unattended work
through locally feasible gaps. **#15 is still not fully qualified.** This follow-up
adds executable qualification at the existing coordinator/setup/runtime boundaries;
no production task, identity, storage or inference policy changed.

## Actual MLX activation interruption

```sh
bash scripts/model-smoke.sh --package-only
python3 scripts/qualify-model-lifecycle.py \
  --source "$HOME/Library/Application Support/Tidy/QualificationModels/50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b"
```

The opt-in driver creates two isolated APFS clones of the already-approved local
weights, with distinct file inodes. Both are the **same artifact**, under the
original and a qualification-only revision alias. It retains a canary outside
those directories. The packaged worker uses actual `ModelSetup`, integrity
verification, `MLXLocalModelRuntime` loading/readiness inference and selection
commit. Its transfer implementation rejects every request; network is separately
denied and checked, as is the build-resource fallback.

Unlike the older controlled-runtime termination checks, the commit callback is
reached only after the real candidate container has loaded and passed native
readiness inference. The original model is still loaded while that preparation
runs. The diagnostic wrapper then kills only its own process:

| Checkpoint | Fresh-process observation, three repetitions each |
| --- | --- |
| Verified candidate ready, before selection write | Original selection retained; fresh process verifies it, reaches Ready and completes actual JSON inference. |
| Selection written, before runtime activation returns | Candidate alias retained; fresh process verifies it, reaches Ready and completes actual JSON inference. |

**Six SIGKILL cases and six fresh-process restorations passed.** Every clone hash
was checked after each case, the unrelated canary remained exact, and all 11
approved-source hashes were unchanged. The parent imposes a 90-second child timeout
and removes only the two explicitly created clone directories. Selection, canary,
per-checkpoint logs and result hashes remain for inspection.

This is real-MLX activation-boundary evidence using one approved artifact. It is
not two independently reviewed production versions, SIGKILL during transfer or
arbitrary in-flight tensor operations, power loss, true memory pressure or a
formal native offline walkthrough. No model download or installed-app mutation
occurred.

## Actual ENOSPC at the task/journal boundary

Reused the previously approved 256 MiB case-sensitive APFS sparse image, mounted
only at its owned worktree mount point. The new test is disabled unless explicitly
given `TIDY_DISPOSABLE_VOLUME`. Before filling anything it verifies the argument is
the actual mount root, is on a different filesystem from `/`, and has total capacity
at most 300 MiB. It creates only a unique owned subdirectory and bounded filler.

```sh
env TIDY_DISPOSABLE_VOLUME="$PWD/.build/remaining-qualification/volume-check/mount" \
  swift test --disable-automatic-resolution \
  --filter exhaustedJournalVolumePreservesFilesAndDurableHistory
```

The serial parameterized test first establishes a real completed/undone history
record, then fills its journal volume until writes of 1 MiB, 4 KiB and finally one
byte return **ENOSPC**. It attempts either a new task or undo through the public
coordinator. It checks:

- The fixture exists at exactly one original/resulting location with exact bytes.
- A refused journal write leaves the prior durable journal bytes exact.
- After reclaiming only the owned filler, a fresh coordinator reads retained
  history, recovers the newest operation and can explicitly undo/retry safely.
- Prior history remains present; no manual history repair or file restoration is
  substituted for coordinator recovery/undo.

Both final optimized cases observed journal refusal: execution reported no change
and undo refused before reversing the file. Both preserved source and prior journal
bytes, and fresh retry/undo passed. Final debug coverage also observed successful
small operations after the filler had encountered ENOSPC; those durable outcomes
were independently recovered and undone. Neither outcome was silently relabeled.

### Failed harness assumptions retained

The initial harness omitted the coordinator's required inventory refresh after a
completed task, producing `writeGrantRequired` before the intended probe. That was
corrected without changing application authorization.

The first capacity probe stopped after a large write failed; smaller allocations
could still succeed. The filler was tightened down to one-byte writes, but APFS
could still reclaim capacity between exhaustion and the operation during a full
suite run. The correct test therefore accepts **durable success or safe refusal**,
not an unconditional error merely because an earlier write hit ENOSPC. Earlier
focused observations of actual journal refusal remain separate evidence.

An early retry kept the filler descriptor open after unlinking, preventing capacity
reclamation; it now closes before removal. Another harness assertion demanded every
historical record remain non-uncertain after a newer task reused its paths; that
contradicted conservative historical identity semantics. It now verifies the newest
record is recoverable and the prior record remains retained, without rewriting
older identities. No production behavior was weakened to accommodate these probes.

The filler and each unique test directory were removed. Existing image fixtures
were retained and the image was detached. This is not a hard host I/O bound, disk
failure/power-loss proof, an exhaustive every-write ENOSPC matrix or TCC revocation.

## Full local verification

Final full debug and hosted optimized pipelines passed with provider, diagnostic
identity and disposable-volume tests **enabled, not skipped**:

- **130 coordinator functions in 17 suites**, including both ENOSPC variants;
- **16 model, 2 worker, 18 workspace functions**;
- packaged full actual-model smoke and parser containment/fixture-worker smoke;
- lint, diff whitespace and Python syntax checks.

The original versioned corpus and production prompt/parser were not changed by
this follow-up; no new naming score is inferred. Provider metadata after the full
tests still showed both authorized cloud-only controls dataless/NotDownloaded and
not downloading; downloaded controls remained current. Approved source weights
were rehashed unchanged and the disposable image is detached.

Local evidence: `.build/native-matrix/model-lifecycle-parent.log`,
`.build/model-lifecycle-2hlygtqj/`, the retained `storage-exhaustion-*.log` attempts,
`lifecycle-resource-{debug,optimized}-verified.log`, packaged smoke logs and
`lifecycle-resource-summary.json`. Earlier failed full-suite harness attempts are
retained rather than presented as passes. No CI, merge or release occurred.

## Remaining prerequisites — do not silently mark #15 complete

| Remaining gate | What is actually needed |
| --- | --- |
| Durable filesystem identity | A qualifying public volume-incarnation/lifetime contract or an explicit owner-approved redesign. The approved feasibility STOP remains; no timestamp tolerance or weaker identity fallback was implemented. |
| Genuine sandbox/TCC revocation | A real per-app revocation surface for the selected-folder grant, or a suitable separate test configuration. The isolated app exposed no control. Bookmark deletion, POSIX denial or TCC reset are not substitutes. |
| Independent representative naming assessment | An independent human reviewer and representative authorized material. Another agent or the fixed synthetic script cannot supply independent human scores. |
| Minimum supported hardware/macOS | Actual executions on the intended minimum configurations. This M4 Max/macOS 27 host cannot establish an older OS or lower-memory Mac's runtime behavior. |
| True memory pressure | A dedicated suitable test environment or an explicitly approved bounded pressure budget. The repeated-workload run and same-artifact activation tests do not qualify system-wide pressure; none was induced on the shared Mac. |
| Genuine production-version replacement | A second reviewed production artifact with manifest/integrity/terms approval. Revision aliases of identical weights do not supply that resource. |

The formal undo-cancellation, native-offline and diagnostic-export reruns remain
owner-deferred; they were not reinstated. #18 accessibility/system effects remains
separate and deferred, and #16's experimental-beta distribution disposition is
unchanged. These missing resources/decisions prevent an honest aggregate closure;
the local implementation work must not manufacture passes or broaden hardware claims.
