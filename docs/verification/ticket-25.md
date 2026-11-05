# #25 — OCR identifier/date extraction

## Owner disposition — 2026-11-04

Owner directed **wontfix / not planned for now**, with the limitation retained for
later reconsideration. This is not an implemented fix or a qualification pass.
Keep safe abstention; I01/S01 remain missed opportunities in the reviewed run.
Revisit only on owner request or new evidence of a supported isolated OCR/cache
configuration or an explicitly reviewed alternative backend. Do not reopen the
investigation automatically or grant shared-cache access to work around it.

2026-11-03. **Implementation investigation, not fixed.** Original I01/S01 inputs
and the [diagnosed safe abstention](stable-v1-abstention-diagnosis.md) remain
unchanged. No successful new naming output or benchmark improvement is claimed.

## Regression seam and red baseline

A temporary public-coordinator test recreated the fixed corpus's exact Helvetica
36-point raster and 800×300 PDF embedding. It selected the first actual extracted
heading through a controlled naming response; it did not supply corrected text or
identifiers. It required the original expected filename, byte preservation and
reopened undo for both cases.

```sh
swift test --disable-automatic-resolution \
  --filter invoiceOCRPreservesOriginalIdentifierAndDate
```

Both cases failed before any production change: zero changes instead of one.
This confirms an extraction regression seam independent of actual-model title
selection. The diagnostic/regression patch is retained locally under
`.build/native-matrix/ticket-25-probe-and-red-regression.patch`; the unimplemented
test is not left failing in the normal suite or disguised as a skipped pass.

## Probes within unchanged containment

Each alternative was tested separately; none recovered both original identifiers
and dates in the coordinator regression:

| Probe | Observation |
| --- | --- |
| Accurate recognition, revision 3, explicit CPU compute stages | Returned unreadable; no names. |
| Accurate recognition, revision 2 | Regression still failed. |
| Accurate recognition without automatic language detection | Regression still failed. |
| Accurate recognition with deprecated CPU-only selection, diagnostic only | Regression still failed. Deprecated API not retained. |
| Fast recognition with high-quality redraw to 2048 pixels | I01 remained fused; S01 additionally misread the date (`2026fj3-14`). Rejected as a fix. |
| Fast recognition redraw to 1024 pixels | Regression still failed. |
| Fast recognition, revision 1 | Regression still failed. |
| Fast recognition with language correction | Regression still failed. |
| Fast heading region of interest / cropped heading | No original-cases improvement demonstrated. Diagnostic crops are not a whole-image coverage implementation. |
| Tight diagnostic crop around I01's identifier | Still recognized `A1901` with confidence 0.5, not `AI901`. No identifier replacement rule was added. |

Scoped OS logs from the test helper processes show accurate-recognition failures
in `e5rt_e5_compiler_create` (Code 11) and underlying detector loading, alongside
denied cache-directory initialization (`errno = 1`). Cache-directory warnings
also occur on functioning fast-recognition paths, so those warnings alone do not
prove the exact missing permission or establish that a cache allowance fixes the
compiler failure. The helper catch returned `unknownError`/`nilError`; no successful
accurate-recognition output is claimed.

These probes do not prove that every geometry, preprocessing or recognition
strategy is impossible. They show that the measured candidates are not safe fixes.
In particular, recovering a separator alone does not recover the misread letter.

## Constraint requiring review before broader experiments

The issue explicitly requires containment/resource tradeoffs to be reviewed, not
silently introduced. A private, bounded, disposable compiler-cache/scratch allowance
is a possible **next experiment**, not an established solution. It would need an
explicitly approved policy, strict ownership/cleanup, no network or personal-file
access, and validation of whether untrusted content can enter retained artifacts.
No such write grant, shared-cache access or permission change was introduced here.
No new OCR dependency or corpus-specific repair was added.

## Cleanup and verification

All temporary helper settings, hard-coded crop probes and debug output were removed.
Production helper and OCR tests match the pre-investigation source exactly. Earlier
unrelated local #15 changes are preserved. Full `OCRNamingTests` passed afterward,
including the fused-token refusal and positive image/PDF cases; the packaged
diagnostic was rebuilt cleanly. Lint and whitespace checks passed.

No full-corpus improvement run is reported because no candidate met the focused
regression. Previously reviewed outputs and denominators remain unchanged. No
commit, push, merge, release or issue closure occurred during this investigation.

Raw evidence under `.build/native-matrix/` uses `ticket-25-` prefixes: red baseline,
each failed alternative, accurate error, restored OCR baseline and clean packaging.

## Owner-approved private scratch trial

The owner subsequently approved a **diagnostic-only** bounded private scratch
experiment, not a production permission change. A fresh 128 MiB HFS+ sparse image
provided a separate filesystem with **134,176,768-byte reported capacity**. Its
parent and individual request directories were private; only that request's
directory was writable by the diagnostic parser. System/runtime and own-bundle
reads matched the baseline, and network, outside-file access, fork and exec remained
denied. HOME/CFFIXED_USER_HOME and temporary/cache environment variables were
pointed at freshly created request-owned directories.

The standalone probe reproduced the native image/PDF rendering and recognition
settings. It used a diagnostic 10-second alarm/12-second parent timeout rather than
changing the production three-second budget. Final observations completed within
about 0.06–1.01 seconds. All material was the original synthetic I01/S01 bytes.

| Observation | Result |
| --- | --- |
| Fast revision 3, both original inputs | Recognition succeeds and reproduces `A19012026-10-01` / `P13012026-03-14`. |
| Accurate revisions 1, 2, 3, both inputs | Recognition fails; no extracted heading. |
| Accurate revision 3 with background processing disabled | Still fails for both inputs. |
| Final fast/accurate controls, both inputs | All four cases allow a scratch write and reject a loopback connection, outside owned-file read and outside owned-file creation. |
| Foundation home/cache paths | Redirected inside the private request directory. |
| Foundation temporary-directory path | Still resolves to the normal system temporary directory despite the supplied environment; access there was **not** granted. |
| Scratch artifacts after each final request | Only the explicit 32-byte synthetic write-control file; no compiler cache files appeared. |

PID-scoped system events from the final accurate processes still report denied
Metal cache-directory initialization and underlying text-detector loading errors.
The earlier no-scratch accurate tests also reported E5 compiler initialization
failures. The approved private allowance alone therefore **does not enable accurate
recognition**. These observations do not identify every internal path or prove
which additional permission would be sufficient. They do not justify granting
access to shared system/user cache locations.

No source headings/identifier strings were found in the final request files, which
contained only the explicit write control. Since accurate OCR failed before creating
compiler artifacts, this is **not** a successful compiler-cache retention or privacy
qualification; encoded data, OS-wide logs and forensic disk remnants were not
examined. Raw synthetic OCR replies were intentionally retained in diagnostic logs
outside the disposable volume, not in production logs.

### Failed probe controls

Early standalone probes crashed in ImageIO before OCR because their initial
read scope omitted the baseline's own-bundle asset access. Matching that existing
read scope eliminated the probe crash; it is not evidence that accurate OCR itself
crashed or that broader personal-file reads are needed. Initial network controls
incorrectly treated socket creation as a connection attempt. They were corrected
to require a denied loopback `connect`, as in the existing offline smoke; all final
controls passed. Initial attempts/results are retained separately.

### Scratch cleanup and disposition

All explicitly created request directories were removed, the volume detached and
the exact owned scratch image unlinked. Prototype source, settings, scoped events
and results remain under
`.build/ocr-scratch-trial-237e9ab9c8a34666a34430fcfcd02b84/`, with
`final-controlled-results.json` and `summary.json`. Production source, parser
permissions and the corpus are unchanged. #25 remains **unimplemented**; next work
requires investigation of a supported isolated compiler/cache configuration or an
alternative bounded OCR backend, not blind identifier repair or shared-cache grants.

## Public API research follow-up

[Primary-source API review](ticket-25-cache-research.md) found no documented
end-to-end configuration that routes all built-in Vision compiler/cache activity
into a caller-owned directory or guarantees cache-disabled/memory-only operation.
This is not proof of impossibility. Apple's reviewed libc source explains why
setting `TMPDIR` is not sufficient: Darwin temp resolution asks dirhelper first,
then uses the environment fallback only on failure; cache resolution has no
equivalent environment override in that source.

CPU controls, compiled models, warmup and newer native text-request APIs do not
provide the missing documented routing/resource contract. No private interposition,
forced directory-service failure, shared-cache grant or new backend was introduced.
The recommended next escalation is an owner-approved Apple support inquiry with
the synthetic reproducer, or separate review of an alternative OCR dependency and
its bounds. Nothing was submitted externally. At that point #25 was open and
unfixed; the later owner disposition above closes it as wontfix/not planned,
without implementing a fix or authorizing further investigation.
