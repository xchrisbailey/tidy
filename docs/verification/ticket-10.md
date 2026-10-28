# #10 — provisional bounded native PDF evidence

2026-10-28. **Not release qualification or issue closure.** Started clean on
`ticket/10-pdf-evidence` at the requested `integration/tidy-v1` base `51ae6fd`.
No dependencies, model download, cloud inference, CI, OCR, diagnostics feature,
or primary user documentation added. Native GUI tools are unavailable.

## Implemented path

`TaskCoordinator.planTask(request:model:)` remains the application seam. Only
selected, authorized content-naming files reach `inspectContents`. `.pdf` dispatch
uses the existing `readInspectionInput` snapshot/ancestor/provider checks and
read-only no-follow bounded reads, then a separate `TidyInspectionHelper` process.
The helper receives only capped bytes over an anonymous socket, not a source
path, root descriptor, request, model, operation authority or journal access.
Parsing uses real local PDFKit, never document-wide `PDFDocument.string`.

Encrypted (including owner-only encryption), locked and copying-restricted PDFs
abstain. No password, unlocking, rasterization, OCR or permission bypass is used.
Malformed files, empty/image-only pages and excessive extracted evidence abstain.
Unsupported extensions remain unopened. A valid PDF header is required.
Only the first three pages are extracted; coverage is `wholeDocument` or
`first3PagesOnly`, passed explicitly to the existing model as untrusted evidence.
Later pages are not inspected for text, dates or identifiers. This is not a claim
that PDFKit lazily parses only three pages internally. Coverage is currently in
the transient naming input, **not a newly implemented results UI disclosure**.

The existing naming validator, one task-wide replacement allowance, language
policy, protected tokens, extensions, collision allocation, complete-plan
validation, execution snapshots and persistent undo remain the only naming and
mutation path. PDF bytes are never rewritten. Evidence stays transient and
non-Codable; only ordinary resulting filenames/operation metadata enter history.
No extracted temporary files or app content logs are created. Native stderr is
discarded and process errors reduced to allowlisted inspection codes. OS crash
reports, swap and native framework behavior are not a secure-erasure guarantee.

## Initial limits (qualification defaults)

| Resource | Implemented policy |
| --- | --- |
| Compressed PDF input | 20 MiB/file, 40 MiB/task, plus at most a rejection sentinel byte in shared reads. Oversized preflight sizes stay unopened. Separate from the existing 64 KiB text-input task allowance. |
| Pages | First 3 pages total; no OCR. |
| Extracted text | 16,384 UTF-8 bytes/file; oversize rejects, not silently truncated. Shared 65,536 accepted evidence bytes/task across text/PDF. |
| IPC reply | Parent independently caps 100,000 bytes, allowing JSON escaping overhead; excess rejects and kills the worker. Helper also caps its encoded reply. |
| Concurrency | One serial helper per file in the existing content loop. No detached parser tasks. |
| Time | Parent supervises a 3-second helper deadline, within the shared 5-second cumulative inspection budget. Existing 1-second cooperative filesystem-read and 45-second content-stage clocks remain. |
| Cancellation/cleanup | Parent polls task cancellation/deadline during nonblocking IPC; every launched child is SIGKILLed if still running and synchronously reaped before return. An independent helper 3-second fail-stop also handles parent death. |

The helper disables core dumps before parsing and applies a profile denying
network, file writes, process fork/exec and file reads except its own installed
bundle and system framework/library resources. The app closes source descriptors
on exec. All helper input is authorized, capped in-memory data. No parser fallback
runs if containment cannot initialize.

These are **not proven hard wall-time or unified-memory bounds**. PDFKit can
allocate internally before returning a page string; no qualified Darwin process
memory limit is implemented. The compressed input cap does not bound expanded
PDF memory. Process launch, synchronous filesystem/provider operations,
termination/reaping, watchdog scheduling and OS shared memory remain subject to
OS latency. No abandoned-worker timeout race is used. Controlled hanging-worker,
oversized-IPC/crash stress, parent-death and peak-memory tests remain open.

## Critical native launch blocker — do not ship as qualified

The deterministic coordinator tests run the helper directly and its own sandbox
profile initializes successfully. The signed diagnostic initially inherited App
Sandbox helper entitlements under a non-App-Sandbox parent, causing a native
libsecinit startup trap. Diagnostic packaging now signs its helper without those
inheritance entitlements; production packaging signs inside-out with
`app-sandbox` + `inherit`, then verifies both signatures.

Subsequent packaged offline qualification found that applying the additional
helper sandbox under the smoke launcher's existing sandbox fails with
`sandbox initialization failed: Operation not permitted`. The actual blocked
invocation was:

```
env NSUnbufferedIO=YES bash scripts/model-smoke.sh
```

Workdir: `/Users/chris/dev/utils/tidy-ticket-10`. Once diagnosed, this blocked
invocation was not repeated. No containment restriction was removed to make that
gate pass. Early failing runs are failures, not successful offline qualification.

**The production App Sandbox child arrangement is therefore NOT qualified and
must not be assumed operational.** A helper unable to install its additional
profile fails closed; no in-app parser or unsandboxed parsing fallback exists.
An independently sandboxed native service/launch design (likely an XPC service)
must be designed and verified before release. Correct signatures alone do not
prove runtime launch/containment compatibility. Keep #10 and the stronger #1
resource/privacy gates open; #11 must inherit this blocker, not silently bypass
it. The existing default model smoke excludes the opt-in PDF qualification, so
this provisional path does not turn the established metadata/text smoke into a
known failing check. `--package-only` prepares the signed diagnostic without
launching it or accessing the network.

## Red → green and local evidence

At the agreed coordinator seam, a real generated native invoice PDF initially
produced no change because PDFs were unsupported (recorded red). The helper path
made that test green with actual PDFKit text, protected date/ID/extension,
byte-for-byte unchanged contents, reopened undo and persistent-state canary
checks. Additional generated report and Spanish invoice examples pass, along
with malformed, locked/owner-protected, empty, oversized input, excessive extracted
text, and four-page coverage cases. Collision/numbered suffix, explicit model
abstention, embedded-instruction resistance, invalid path rejection and
cancellation during naming preserve existing restrictions. Existing text's
unsupported fixture now uses RTF because PDF is no longer an unsupported format.

The test fixture generator uses CoreGraphics/CoreText; it draws real separate
lines and explicitly large page boxes for extraction-size cases, rather than
assuming clipped off-page glyphs become readable evidence. Temporary synthetic
fixtures are removed. Tests do not assert exact full PDFKit strings.

The actual pinned candidate was reused from
`~/Library/Application Support/Tidy/QualificationModels`, without download:
`mlx-community/Qwen3-4B-Instruct-2507-4bit`, revision
`50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b`; MLX Swift LM 3.32.3,
MLX Swift 0.32.3, Transformers 1.3.5. Host: Apple M4 Max, 36 GiB, macOS 27.0.1.
After the nested-sandbox block, a distinct direct signed diagnostic invocation
`.build/TidyModelSmoke.app/Contents/MacOS/TidyModelSmoke --pdf-evidence` attempted
the complete real-model task without the outer offline sandbox. It failed safely
with `PlanningError.invalidResponse`; this is **not a passed naming gate, nor an
offline/network-denial proof**. No raw prompts, responses or excerpts were logged.
The real-model PDF path is intentionally opt-in so this failure remains visible
without weakening validators or the one-replacement policy.

## #11 handoff

- Keep `inspectContents(_:root:budget:)` and `readInspectionInput` as the only
  content/authority dispatch. Return the existing transient
  `InspectionEvidence(kind:text:coverage:)` into `resolveContentNames`; do not
  add a parallel planner.
- `inspectNativePDF(_:budget:)` owns parent supervision and bounded IPC.
  `TidyInspectionHelper` owns native parsing and fixed-code replies. Resolve the
  native sandbox launch blocker before extending/claiming production readiness.
- PDF native text currently has first-three-page coverage and strict protected
  document rejection. OCR must share those pages, text, input and time budgets;
  it must not unlock documents or inspect extra pages after native extraction.
- `InspectionBudget.remainingPDFBytes`, `remainingEvidenceBytes` and
  `remainingTime` are task-wide; text input retains its separate existing cap.
  Add image/pixel/render limits explicitly; none exist here yet.
- No new diagnostic categories were introduced. #14 keeps allowlisted codes;
  generic inspection explanations now cover PDF as well as UTF-8 failures.

## Remaining gates

Native GUI unavailable: no picker/consent, disclosure, progress/cancel, keyboard,
VoiceOver or process-restart UI check. Production sandbox service launch, offline
PDF smoke, actual-model PDF usefulness, minimum/macOS 14 hardware, real providers,
representative long/malformed PDF memory/latency, blocked-parser cancellation and
worker cleanup stress, source-race stress, broader languages, 90% usefulness/80%
cryptic coverage and 100-file/60-second qualification remain open. Deterministic
cancellation during naming is not claimed as blocked-PDFKit cancellation proof.

Final commands/results and integrated commit ancestry are recorded below after
the integration merge.
