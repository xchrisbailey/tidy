# #11 — native image and scanned-PDF text recognition

2026-10-28. Provisional implementation, **not issue closure, corpus qualification
or release approval**. Started clean on `ticket/11-native-ocr` at requested
`integration/tidy-v1` base `67b25f0`, including #10's working independent XPC
inspection service. No dependencies, model download, cloud inference, CI, primary
user documentation or unrelated work changed. The existing pre-submission app
disclosure now includes supported images and scanned PDFs.

## Application behavior and authority

`TaskCoordinator.planTask(request:model:)` remains the agreed test/application
seam. Only authorized, selected content-naming inputs reach `inspectContents` and
the existing `readInspectionInput` snapshot/ancestor/provider/no-follow/capped-read
path. Inventory is still metadata-only. Unsupported extensions remain unopened;
an eligible extension is not a promise that its actual bytes are supported.

ImageIO and Vision run **only in the separate native parser**, never in the app
or XPC broker. The broker receives already-authorized bytes, a format allowlist
value and random request ID, not source paths, root descriptors, bookmarks or
mutation authority. ImageIO checks actual type against the authorized extension
family and rejects multi-image sources before decode. An oriented thumbnail,
not the original full-resolution image, is passed to recognition; EXIF transforms
are not applied a second time. Recognition uses Vision revision 3, fast mode,
automatic language detection, disabled language correction, CPU selection for
every exposed compute stage and a non-caching software Core Image context.

PDFKit checks encryption, lock and copying restrictions **before any extraction
or rendering**. Owner-encrypted scans also abstain. Native text is preferred;
only pages with empty/whitespace-only native text are rendered for OCR. Sparse or
garbled nonempty native text is not replaced speculatively. Native text and OCR
share the same first-three-page selection and all input/text/time budgets; no
second pass visits later pages. Rendering uses a checked crop box, a white-filled
8-bit RGB bitmap and CoreGraphics' crop/rotation drawing transform. Blank OCR
pages may contribute no text, but the combined file must contain enough evidence.
Coverage describes inspected pages, not proof that every mark was deciphered.

Recognized material enters the existing transient `InspectionEvidence`, grounding,
language precedence, title/name validation, single task-wide replacement allowance,
collision allocation, complete-plan execution, results and persistent undo.
Embedded instructions remain untrusted evidence, never scope/actions/language
authority. Extensions and source bytes are unchanged. Confidence is not truth:
we do not repair ambiguous OCR IDs, infer missing words or dates, or claim general
scene understanding. A detected low-confidence observation rejects that file;
empty/insufficient evidence abstains rather than authorizing a guessed name.

## Initial bounds for #15 qualification

| Resource | Implemented policy |
| --- | --- |
| Formats | PNG (`.png`), JPEG (`.jpg`/`.jpeg`), HEIC/HEIF (`.heic`/`.heif`), single-image TIFF (`.tif`/`.tiff`), PDF. Actual ImageIO type must match the extension family; HEIC/HEIF share a family. GIF, WebP, camera RAW, animated/multipage sources and arbitrary ImageIO formats are not enabled. |
| Compressed input | 20 MiB/file; **40 MiB/task shared by images and PDFs** in the inherited `remainingPDFBytes` allowance. Actual reads are capped, with at most a rejection sentinel byte. Text retains its separate 65,536-byte input allowance. |
| Source image dimensions | Positive integer width/height, each at most 16,384, product at most **40,000,000** pixels. The side bounds make multiplication safe on supported 64-bit Macs. Invalid orientation values reject. |
| OCR bitmap | Longest side at most 2,048, at most 4,194,304 pixels; image thumbnail dimensions rechecked after decode. PDF output allocation at most 16 MiB for an RGBX bitmap, excluding framework copies/intermediates. |
| PDF rendering | First 3 pages total, including native-text pages. Finite positive crop dimensions at most 14,400 points each; absolute crop origins at most 14,400; only quarter-turn PDF rotation. Scale at most 2 pixels/point and at most 2,048 pixels on the longest side. |
| Retained evidence | 16,384 UTF-8 bytes/file, rejected rather than silently truncated; 65,536 accepted evidence bytes/task shared across text/PDF/images. Individual OCR observations and combined PDF text are checked before accumulation. At least eight letters; non-whitespace control characters rejected again by the app. |
| OCR confidence | Every returned top candidate must have confidence at least 0.5. This is a provisional abstention heuristic, not calibrated accuracy or assurance that all text was detected. |
| Response | 100,000 actual pipe bytes including JSON overhead, enforced by supervisor and app. Successful replies require supported source-kind/coverage, bounded usable text and the existing deadline/cancellation checks. |
| Time/concurrency | Existing single serial parser; 3-second app/broker/worker supervision within the **shared 5-second cumulative inspection budget**. Read preflight retains its cooperative one-second clock; entire content stage retains 45 seconds including local naming. No OCR-specific extra page/time/input allowance. |

These bounds cap our input/output and explicitly allocated render buffers, **not
ImageIO/PDFKit/Vision/Core Image internal expansion, total unified memory or hard
wall time**. Image metadata parsing, decompression, drawing and recognition are
synchronous inside a killable process. OS launch, scheduling, kill/reap, source
I/O and broker-failure grace remain subject to #10's limitations. No qualified
Darwin hard memory ceiling or minimum-hardware latency claim is added.

## Containment diagnosis and actual packaged checks

The coordinator PNG fixture first went red as unsupported; enabling the native
path exposed accurate recognition's E5 compiler initialization failure under the
restricted profile. Synthetic-only development probes observed denied cache
lookups. Fast CPU recognition passed the same read/write/network-denied profile;
no home, temporary-directory, cache-write or blanket filesystem grant was kept.
Accurate recognition is deliberately not offered as an unsandboxed fallback.

The first actual packaged XPC smoke still went red with an Objective-C exception
inside Metal binary-archive initialization, reduced by the supervisor to safe
abstention. CLI tests alone had missed this service-bundle-layout behavior.
The parser now lives at `Contents/Helpers/TidyInspectionHelper` inside the service,
not beside the broker in `Contents/MacOS`. That layout passed actual native PNG
and scanned-PDF coordinator naming under the App-Sandbox diagnostic parent.
Temporary metadata permissions, HOME/cache overrides, syscall interposition and
all tagged development instrumentation were removed; the passing result was
rechecked with the original restrictive profile. The fixed exec allowlist names
the new parser location. This is measured on this OS, not a documented guarantee
for every future Core Image/Metal version.

`inspection-smoke.sh --fixture-workers` first runs real native PDF, PNG and
scanned-PDF naming/byte/reopened-undo checks with networking denied. Controlled
workers in the disposable diagnostic bundle then exercise stopped-worker deadline,
cancellation acknowledgement, oversized IPC, signal crash, malformed JSON,
control-character evidence and actual source-read/write/loopback denial. Existing
external no-parser-after-return and observed-parser/abrupt-parent-exit cleanup
checks remain. Controlled workers are never packaged in the production app or
actual-model diagnostic. Inside-out helper/service/app signing and deep strict
signature verification remain required.

## Local evidence

Four new coordinator test functions cover 27 cases, using actual temporary images,
real native Vision and image-only PDFs, not a fake recognizer: PNG, uppercase JPEG
extension, HEIC, TIFF, scan, EXIF and PDF quarter/half turns, Spanish evidence and
source-language precedence, first-three-page canary exclusion, instruction-containing
text, path-injection rejection, collision suffixes, cancellation during naming,
reopened undo, unchanged bytes and persistent-store snippet-canary checks. Limit
fixtures include malformed/type-mismatched/unsupported inputs, blank images, a
severely downsampled real text image, 20-MiB overflow, 16,385-pixel width,
40.96-megapixel source, multi-image TIFF, locked/owner-encrypted scans, excessive
PDF rendering box and three padded 16-MiB images exhausting the 40-MiB task cap.
These synthetic fixtures do not replace representative photographs or real scans.

Scanned PDF naming independently went red as insufficient before rendering/OCR,
then green at the coordinator with the correct native evidence, protected tokens,
source-kind/coverage, persistent-state checks and byte-preserving reopened undo.
Existing text, PDF, metadata, recursive, history, diagnostics and supervisor tests
remain intact. New malformed/native-text response probes validate app-side reply
checks rather than trusting even a successful helper envelope.

The approved candidate was reused from
`~/Library/Application Support/Tidy/QualificationModels`, without download:
`mlx-community/Qwen3-4B-Instruct-2507-4bit`, immutable revision
`50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b`; MLX Swift LM 3.32.3,
MLX Swift 0.32.3, Transformers 1.3.5. Host: Apple M4 Max, 36 GiB,
macOS 27.0.1. Actual OCR + actual-candidate + coordinator checks passed PNG,
scanned PDF and Spanish PNG naming, exact protected date/ID/extension validation,
useful grounded descriptors, unchanged source bytes and reopened undo, offline
with original build-product reads denied. A targeted complete three-example run
took 12.411 / 10.652 / 12.285 seconds per task; these are tiny synthetic tasks,
not a benchmark gate. Model loaded physical footprint was about 2.54 GB, not
measured native-parser peak memory.

Earlier runs remain failures: accurate-mode initialization, the packaged Metal
crash, and one invalid actual-candidate scanned-PDF response after a PNG success.
The scan diagnostic now uses the existing evaluated explicit PDF request; the
general model/validator/replacement policy was not weakened. A subsequent full
run passed all six PDF/OCR examples, existing text naming and metadata checks,
but hit the harness's 120-second command timeout before completing remaining
checks. That interrupted run is not a complete pass.

The final **complete** run, with a 300-second command allowance, passed all prior
model lifecycle, PDF/text naming, metadata, task chains, filename-month naming,
clarification/refusal, context-bound rejection, recursive collisions/undo and
cancellation checks, plus all three OCR tasks. Final OCR PNG / scan / Spanish
tasks took 13.563 / 11.202 / 10.474 seconds, respectively; native generation
cancellation quiesced in 0.308 seconds. No raw completion was logged and no
validator or replacement allowance was relaxed.

## Final integrated checks

`git merge --no-edit integration/tidy-v1` reported already up to date at
`67b25f0`. No issue was closed, no push/CI was run and no model was downloaded.

| Command | Result |
| --- | --- |
| `swift test --disable-automatic-resolution` | Passed: 92 reported core tests with one existing real-provider skip (91 executed), 11 model tests and 2 supervisor tests: **104 non-skipped reported tests**. New OCR coverage comprises four test functions / 27 cases. |
| `bash scripts/lint.sh` | Passed strict formatting, five plists and shell syntax. |
| `git diff --check` | Passed. |
| `bash scripts/build-app.sh` | Passed arm64 app packaging, bundled MLX resources, inside-out helper/XPC/app signing and deep strict verification. |
| `env NSUnbufferedIO=YES bash scripts/inspection-smoke.sh --fixture-workers` | Passed real PDF/PNG/scan naming and undo under App Sandbox, all seven worker cases, effective read/write/network denials and abrupt-client-exit cleanup; no parser remained after probes. |
| `env NSUnbufferedIO=YES bash scripts/model-smoke.sh --ocr-evidence-only` | Passed all three actual-native/actual-candidate OCR examples, offline, protected tokens/bytes/language/extension and reopened undo. |
| `env NSUnbufferedIO=YES bash scripts/model-smoke.sh` | Final expanded complete run passed all prior checks plus OCR; used 300-second harness allowance. The earlier 120-second interrupted run remains recorded above. |

## #15 handoff and open gates

- Application seam: `TaskCoordinator.planTask(request:model:)`, existing execution,
  result categories and reopened undo. No new diagnostic UI or public reason code.
- Dispatch: `inspectContents(_:root:budget:)`, shared `readInspectionInput`, then
  `inspectNativeDocument(_:format:budget:)`. The historical PDF-byte budget now
  intentionally includes images. Evidence kinds: `plainText`, `pdfText`,
  `pdfTextAndOCR`, `imageOCR`; coverage: existing PDF values or `wholeImage`.
- IPC: `InspectionServiceProtocol.inspectDocument(_:format:requestID:withReply:)`,
  bounded raw bytes and allowlisted format; `cancel` still acknowledges reap.
  `InspectionReply.kind` is optional for failures, required/validated for success.
  `WorkerSupervisor` remains the single pipe/deadline/cancel/kill/reap owner.
- Focused actual candidate: `bash scripts/model-smoke.sh --ocr-evidence-only`,
  optionally `--ocr-example=png`, `--ocr-example=pdf` or `--ocr-example=spanish`.
  `bash scripts/inspection-smoke.sh --fixture-workers` checks packaged containment
  without loading a model. `bash scripts/model-smoke.sh` includes all prior checks
  plus OCR; allow more than 120 seconds for the expanded sequence.

Evidence stays non-Codable/transient outside ephemeral IPC. No extracted image or
text files, content caches, prompt/response logs or history snippets are created.
Resulting ordinary filenames necessarily enter undo history. Native OS diagnostics,
Swift copies, swap and crash reports are not a secure-erasure promise.

Keep #11/#15 open for macOS 14, minimum/lower-memory hardware, native-parser peak
memory/internal-decompression stress, representative poor/sideways/handwritten
and mixed-script scans, language coverage beyond the fast recognizer and existing
naming policy, true HEIF variants, APNG/codec variations, hostile native parser
stress, broader broker/parent-death races, real File Provider nonhydration and
source-race qualification. Recognition auto-language support is OS/revision/mode
dependent; only English/Spanish naming is exercised here. Missing/low-confidence
text can abstain, but confident OCR mistakes or undetected marks are still quality
risks. No universal accuracy or identifier-recovery claim is made.

Native GUI tools are unavailable: picker/write consent, visible disclosure,
progress/cancel, clarification/confirmation, keyboard/VoiceOver and actual
process-restart UI remain human checks. Ad-hoc signing is not Developer ID,
notarization or distribution qualification. The 90% usefulness/80% cryptic naming
corpus and 100-file/60-second minimum-hardware gates remain open.
