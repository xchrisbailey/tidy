# #10 — bounded native PDF evidence

2026-10-28. Operational implementation, **not release/corpus qualification or
issue closure**. Started clean on `ticket/10-pdf-evidence` at requested base
`51ae6fd`; first-pass implementation `3b0f9a9`, verification `2d74a63`, integration
#14 tip `ce039d1` merged in `589f7db`. The first pass's launch/model failures were
software defects, not missing user consent. The follow-up below diagnoses and
replaces that path. No external dependencies, model download, cloud inference,
OCR, CI, primary user documentation or unrelated dirty work changed.

## Application path and source authority

`TaskCoordinator.planTask(request:model:)` remains the application seam. Only
selected, authorized content-naming files reach `inspectContents`. `.pdf` dispatch
uses `readInspectionInput` with the existing snapshot/ancestor/provider checks,
single-link local regular-file policy, capped reads and component-wise no-follow
descriptors. Source descriptors are close-on-exec. Neither source paths, root
descriptors, security-scoped bookmarks nor operation authority cross the native
inspection IPC boundary—only already-authorized, capped bytes and a random
request ID.

The helper uses real local PDFKit and extracts page-by-page, never
`PDFDocument.string`. Encrypted (including owner-only encryption), locked and
copying-restricted documents abstain, without passwords, unlocking, rendering,
OCR or permission bypass. Malformed/empty/image-only or excessive evidence also
abstains. Unsupported extensions stay unopened. A PDF header is required.

Only the first three pages supply text. Coverage is `wholeDocument` or
`first3PagesOnly` in the transient untrusted naming input. Later pages are not
inspected for text/identifiers; this does not claim PDFKit internally parses only
three pages. The existing pre-submission disclosure now includes text-based PDFs,
the three-page limit and protected-document abstention; no new results/diagnostic
UI was added.

The existing naming validator, one task-wide replacement allowance, source/request
language policy, protected names/dates/IDs, exact extension, whole-plan collision
allocation, execution snapshots, confirmation and persistent undo remain the only
naming/mutation path. PDF bytes are never rewritten. No validator was relaxed to
obtain a model pass.

## Diagnosed sandbox failure and replacement

The minimized red command was:

```
env NSUnbufferedIO=YES bash scripts/inspection-smoke.sh
```

Workdir: `/Users/chris/dev/utils/tidy-ticket-10`. A signed App-Sandbox parent
created one native invoice and submitted it through the coordinator; it abstained
with `unavailable` rather than renaming. The original `Process` child inherited
the parent's sandbox, so its stricter `sandbox_init` profile could not be
installed. Apple's SDK explicitly documents this error for an already-sandboxed
process; this was not a harness approval failure. An earlier diagnostic-only
helper signature also incorrectly requested App Sandbox inheritance under a
non-App-Sandbox parent, producing a libsecinit startup trap.

Apple's [Creating XPC Services](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html)
documents the privilege-separation distinction: `NSTask`/`posix_spawn` inherit
sandbox context, while independently launched XPC services can have their own
restrictions.

The replacement embeds `dev.tidy.inspection.xpc` in `Contents/XPCServices`:

1. `launchd` starts `TidyInspectionService` independently, not as an inherited
   `Process` child of the App-Sandbox app. The service has **no** network,
   user-selected-file, bookmark, container or inheritance entitlements.
2. Before accepting any input, the service disables core dumps and installs its
   own stricter OS sandbox. It denies network operations and filesystem writes
   (except the `/dev/null` discard sink), denies file-content reads except its
   own signed bundle and system framework/library resources, and permits exec
   only of its embedded parser. A literal read-only `/` directory descriptor is
   also necessary for dyld startup; it does not grant descendant file reads.
   No global user-directory/metadata/content allowance is present.
3. The broker accepts a bounded `Data` request, starts a separate native parser
   worker which inherits **this restricted profile**, and supervises two
   nonblocking anonymous pipes. The worker does not try to nest another sandbox.
   No parser runs inside the app or broker, and there is no unsandboxed fallback.
4. Deadline, cancellation, excessive output, malformed replies and worker exit
   all end in fixed-code abstention or cancellation. Every launched parser is
   killed if necessary and synchronously reaped by the broker before its reply
   or cancellation acknowledgement. Connection invalidation cancels pending work.
   The parser also has an independent three-second fail-stop if the broker dies.

The launch loop additionally exposed `/dev/null` opening and dyld's read-only
root-directory bootstrap requirements. Both are narrowly allowed, not general
filesystem grants. Pipes avoid Unix-socket dependencies under the no-network
profile. The broker must be able to spawn its one fixed worker; the stricter
standalone test helper's deny-fork/exec policy is not incorrectly advertised as
the broker policy. No input controls executable paths or arguments.

`package-inspection.sh` is shared by app and smoke packaging: sign the parser,
then its XPC bundle, then the containing app, with deep strict verification.
Actual App-Sandbox launch/extraction is tested; signature inspection alone is
not treated as runtime proof. The custom sandbox API/profile is deprecated and
needs OS-version qualification, not an assumption of indefinite future support.

## Limits and privacy

| Resource | Implemented policy |
| --- | --- |
| Compressed PDF input | 20 MiB/file, 40 MiB/task, plus at most a rejection sentinel byte in shared reads. Oversized preflight sizes stay unopened. Separate existing text-input task allowance: 65,536 bytes. |
| Pages | First 3 total, native text only; no OCR. |
| Retained text | 16,384 UTF-8 bytes/file, reject rather than silently truncate; 65,536 accepted evidence bytes/task shared across text/PDF. |
| Worker reply | Broker caps 100,000 actual pipe bytes before accepting a reply, including JSON escape overhead; app independently checks the broker reply cap. The parser also caps encoding. |
| Concurrency | Existing serial content loop; one supervised native parser per request, no detached parser task/timeout race. |
| Inspection clocks | App's helper deadline is at most 3 seconds within the shared 5-second cumulative inspection allowance. Broker independently supervises 3 seconds. Existing 1-second cooperative filesystem-read and 45-second content-stage clocks remain. |
| Cancellation | App awaits broker acknowledgement of parser reap, not just XPC invalidation. On broker failure it allows a four-second fail-stop grace before returning; this is not a hard real-time guarantee. |

These are **not proven hard unified-memory or wall-time limits**. Compressed bytes
do not cap PDFKit's expansion/internal allocations, and there is no qualified
Darwin memory ceiling. Synchronous source/provider I/O, process launch, kernel
termination/reaping and watchdog scheduling still depend on the OS. A broker
crash plus stopped worker, hostile native-code exploitation, system-wide memory
pressure and broader parent-death/race stress need further qualification. Normal
blocked-worker deadline/cancellation and oversized/crashed-worker cleanup are
tested, not merely inferred from post-parse clock checks.

`InspectionEvidence` stays transient and non-Codable. IPC envelopes are ephemeral
only. No extracted files, content cache, prompt/response logs or app-persisted
snippets are created. Native worker stderr goes to a discard descriptor; errors
become allowlisted codes. History retains only ordinary operation names/paths
and identities. Swift copies, OS swap/crash reports and native OS logging are not
a secure-erasure promise. Development inspection used bounded **synthetic-only**
responses; all tagged development instrumentation is removed before final checks.

## Regression coverage and actual-model diagnosis

At the agreed coordinator seam, generated invoice PDF naming went red as
unsupported, then green with real PDFKit text, protected date/ID/extension,
unchanged bytes, reopened undo and persistent-state canary checks. Report and
Spanish invoice fixtures also pass. Other cases cover malformed, locked,
owner-encrypted, empty, oversized, excessive-text and four-page coverage PDFs;
collision suffixes; explicit abstention; embedded instructions; invalid paths;
uppercase extensions; unsupported title dates and extension changes; recovery
within one naming replacement; and cancellation during naming. Existing text's
unsupported fixture uses RTF. Numeric/date preservation remains the established
token-based policy, not a qualified general date parser or named-entity recognizer.

`WorkerSupervisorTests` runs real controlled executables that stop themselves,
terminate by signal, emit an excessive reply or are cancelled. Each assertion
checks the expected error and `kill(pid, 0) == ESRCH` after return. The packaged
`inspection-smoke.sh --fixture-workers` first runs the **real native parser**,
then substitutes a separately built controlled worker only in its disposable
diagnostic bundle. It exercises the production broker/coordinator under App
Sandbox, checks deadline/cancellation/IPC-cap/crash outcomes and unchanged source
bytes, and externally verifies that no parser remains after each case. It also
observes a running stopped parser before abruptly exiting its client and checks
that connection invalidation removes the parser. A final
controlled worker verifies actual denied source-file open, file creation and
loopback connection syscalls under the inherited parser profile. The diagnostic
parent has the production app's folder/bookmark sandbox entitlements with its
network entitlement deliberately omitted; it also verifies an actual denied
loopback connection before the task. Controlled workers are never packaged in
the production app or model diagnostic.

A further transport regression was reproduced before fixing it: unconditional
5-ms sleeps per 4-KiB chunk made a 4-MiB input time out before reaching the worker.
The real-worker test went red at 2.011 seconds; sleeping only under backpressure
made it green in 0.427 seconds, with the exact received byte count and a reaped
process. This does not claim minimum-hardware latency or a hard scheduler bound.

The pinned actual candidate was reused, without download, from
`~/Library/Application Support/Tidy/QualificationModels`:
`mlx-community/Qwen3-4B-Instruct-2507-4bit`, revision
`50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b`; MLX Swift LM 3.32.3,
MLX Swift 0.32.3, Transformers 1.3.5. Host: Apple M4 Max, 36 GiB, macOS 27.0.1.

The real-model red loop found two independent problems: intent generation
invented a PDF-only selection absent from the request (correctly consuming its
one replacement), then naming copied the text-only `.txt` schema example and/or
mistyped `2026-10-28` as `2026-01-28` in its title. Native evidence contained the
correct date; the wrong title was correctly rejected. Naming input now explicitly
carries the authorized `extensionSuffix`; the schema example contains no
text-file extension to copy, and instructions separate a short descriptive title
from exact required numeric tokens in the filename. The final response shape uses
the app-generated source ID and exact per-file extension, not a `.txt` example.
Intent instructions explicitly prohibit inventing selection from inventory and
show the existing `rename+selection` contract for explicit PDF requests. A naming
replacement gets only an allowlisted schema/title/name rejection explanation,
never raw rejected output or another attempt. The validator's conditions and
accepted names are unchanged by classifying those rejections. A transient
`protectedSuffix` copy aid in the text prompt profile supplies deduplicated
literal numeric tokens plus the extension as one JSON string; it does not repair,
append to, or substitute for the returned filename. That aid regressed PDF
completions, so PDF retains its separately evaluated prompt profile without the
field. Both formats use the same naming flow, validator and replacement budget.
Final validation still checks every required token.
Selection feedback also explains that an empty filter requires both empty
evidence and no `selection` clause effect, preserving the existing text flow.
All existing
grounding, extension, selection and one-replacement checks remain. A subsequent full
offline actual-candidate/coordinator invoice task passed with the useful title
`Acme Invoice`, exact protected filename tokens, byte preservation and reopened
undo (7.512 seconds). The failed runs remain failures, not successful gates.

## #11 handoff

- Keep `inspectContents(_:root:budget:)` and `readInspectionInput` as the sole
  content/authority dispatch. Return transient `InspectionEvidence(kind:text:coverage:)`
  into `resolveContentNames`; no parallel planner or source paths in IPC.
- `inspectNativePDF(_:budget:)` owns app-side service deadline/cancellation and
  response validation. `InspectionServiceProtocol` is the narrow bounded-bytes
  XPC interface; `WorkerSupervisor` owns kill/reap and pipe caps inside the broker.
  `TidyInspectionHelper` owns native parsing and fixed-code replies.
- OCR must share first-three-page coverage, protected-document rejection,
  `remainingPDFBytes`, `remainingEvidenceBytes` and `remainingTime`; it must not
  unlock documents or inspect extra pages after native extraction. Add explicit
  image/pixel/render bounds; none exist here yet. Retain the same sandbox service
  packaging and supervision rather than returning to inherited nested sandboxes.
- SwiftPM's command-line test runner has no app/XPC bundle. Its DEBUG-only branch
  runs the same supervisor directly with a self-sandboxed helper. Packaged app
  binaries always use XPC, with no parser fallback.
- No new diagnostic codes or diagnostic/results UI were introduced. #14 remains
  intact; only the existing content-read disclosure adds PDF limits.

## Remaining true release gates

No native GUI tools: picker/write consent, disclosure, visible progress/cancel,
keyboard/VoiceOver and process-restart UI checks remain human work. macOS 14,
minimum/lower-memory hardware, real File Provider nonhydration, representative
long/malformed PDF memory and latency, broker/parent death stress and source-race
stress need qualification. Ad-hoc signatures are not Developer ID/notarization
or distribution qualification. The 90% naming usefulness/80% cryptic coverage
corpus gates and 100-file/60-second minimum-hardware target remain open. The
initial sandbox EPERM is resolved, not left as a consent or human-only gate.

## Final integrated checks

Latest integration tip `ce039d1` is included; `git merge --no-edit
integration/tidy-v1` reports up to date. No issue was closed, no push/CI was run,
and no model was downloaded. All development instrumentation is removed.

| Command | Result |
| --- | --- |
| `swift test --disable-automatic-resolution` | Passed: 88 reported core tests with one existing real-provider skip (87 executed), 11 model tests and 2 supervisor tests: **100 non-skipped reported tests**. PDF tests cover 20 parameterized cases; supervisor tests cover four worker failures plus the 4-MiB transfer regression. |
| `bash scripts/lint.sh` | Passed strict Swift formatting, five plists and shell syntax. |
| `git diff --check` | Passed. |
| `bash scripts/build-app.sh` | Passed arm64 packaging, bundled MLX resources, inside-out parser/XPC/app ad-hoc signing and deep strict signature verification. |
| `env NSUnbufferedIO=YES bash scripts/inspection-smoke.sh --fixture-workers` | Passed real native PDF rename/bytes/reopened undo under an App-Sandbox parent with networking denied; stopped-worker deadline, cancellation, excessive IPC, signal crash, effective read/write/network denials, and observed-worker cleanup after abrupt parent exit. No parser remained after the probes. |
| `env NSUnbufferedIO=YES bash scripts/model-smoke.sh` | **Complete run passed**, offline with original build-product reads denied: three actual-candidate PDF naming tasks (invoice, report, Spanish invoice), existing two-file English/Spanish text naming, metadata tasks, recursive sorting, context rejection, cancellation and model lifecycle checks. Every PDF task checked useful grounded names, exact protected tokens/extension, actual unchanged bytes and reopened undo. |

Final complete run: verified model load 1.838 s; PDF invoice 8.898 s, report
7.614 s, Spanish invoice 9.991 s; English/nested-Spanish text pair 10.925 s.
These are separate tiny synthetic tasks, not a 100-file benchmark. Native
generation cancellation quiesced in 0.049 s. Last Spanish PDF completion:
603 prompt / 51 output tokens, 1.174 s prefill / 1.920 s generation.
The existing upstream MLX resource-bundle mutated-node warning remains nonfatal.

Interim failures included the original launch EPERM, invented/empty selection
annotations, wrong title dates, missing or mistyped protected tokens/extensions,
and a copy aid that helped text but regressed PDF completions. They remain failed
qualification runs; the final full success does not prove statistical naming
reliability or erase those failures. No safety check or replacement budget was
weakened to obtain a pass. No native GUI was launched or interacted with.
