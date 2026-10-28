# #9 — bounded plain-text evidence naming

2026-10-28. **Provisional implementation, not release qualification or issue
closure.** Started clean on `ticket/9-text-evidence` at requested `f0a1a6f`.
Merged integration #8 (`13e9819`) in `b7e1f44`, retaining its captured recursive
authority, component-wise no-follow traversal, executor, recovery and undo.
No dependency, download, cloud inference, CI or primary user documentation added.

## Task behavior

The public seam remains `TaskCoordinator.planTask(request:model:)` with
`PlanCompletion`, real inventory snapshots, immutable complete `SortPlan`, existing
confirmation/cancellation/execution and persistent undo. Metadata sorting,
selection, combined metadata naming rules and explicit recursive scope remain
model-resolved; they were not replaced by a small sentence allowlist.

The existing structured intent adds a single `content` rename rule. Exact user
request evidence and positive naming/content cues authorize this stage; a
sort-only request cannot enable reads or renames. Existing destructive/mixed
request checks remain. Content naming cannot be combined with another rename
rule, but can accompany authorized metadata sorting and selection. Unsupported
combinations must be clarified/declined, not approximated. The UI explains before
submission that requested content naming reads supported text locally, while
inventory itself reads metadata only.

Only selected `apply` files are inspected. Every eligible source still has a
complete source-ID decision. Unsupported contents are not opened. Inspection
failures become per-file abstentions; excluded files remain outside-selection
unchanged, and matching names are already-organized unchanged. Naming uses actual
text evidence, not only case/separator transformations of a cryptic basename.

Document material is a separate untrusted JSON field, never request authority.
The naming reply can supply only one source-ID-bound title/name/disposition, no
paths, actions, folders, scope or explanations. Unknown/duplicate keys, invented
sources, unsupported words, unsafe names and extension changes are rejected.
All names must finish validation before any execution. The task has **one shared
replacement allowance**: an intent replacement consumes it; otherwise a rejected
naming reply can use it once across all files. This is not one retry per file.

### Grounding and preservation

An evidence title has at least two source words and eight UTF-8 bytes. Its words
must occur in retained evidence (prose capitalization may change), but can be
rearranged; requiring a contiguous quotation was unnecessarily restrictive in
the real-model smoke.
Filename words must come from that title, the original basename, required tokens,
or the small grounded descriptor translation vocabulary described below.

Required tokens preserve original recognizable words (except provisional generic
placeholders such as `scan`, `file`, `untitled`, and single-letter placeholders),
all digit-bearing evidence tokens, and capitalized first-line/title words other
than known document descriptors. Identifiers and numeric date spellings retain
their punctuation and Unicode letter/number boundaries: `AB1234` cannot stand in
for `AB123`. No ambiguous date interpretation or extension rewriting occurs.
This conservative policy can abstain on numeric-heavy documents rather than
choosing which numbers are meaningful. Capitalization is a heuristic, **not a
qualified named-entity recognizer or proof of semantic truth**. Evidence-word
grounding prevents invented words, not every possible invented relationship.

Language priority is explicit requested output language, otherwise reliable source
language, otherwise request language. No interface locale is supplied as naming
authority. Native `NLLanguageRecognizer` uses fresh per-call state; source scores
require at least 40 letters, six nonnumeric prose words, probability 0.65 and a
0.2 margin. Request-language recognition uses a lower 12-letter/three-word prose
floor so ordinary short requests remain usable. Short identifier soup deliberately
falls back instead of accepting a confident false language. These are initial
heuristics needing corpus testing.

**Translation is intentionally limited, not unrestricted semantic translation.**
Grounded invoice/receipt/report/contract/letter descriptors have a literal table
for English, Spanish, French, German, Italian and Portuguese. Original names and
IDs are never translated. The model must abstain when a requested translation
cannot be supported by that vocabulary. Other source text remains extractive.
Other output languages, arbitrary descriptor translation, short/mixed-language
and non-space-delimited titles remain product/quality gaps; the issue is not
claimed fully qualified. Explicit requested language must occur in a supported
positive naming-language phrase, not merely an interface-language mention.

## Initial bounds and filesystem authority

| Bound | Implemented behavior |
| --- | --- |
| Formats | `.txt` and `.md`, strict UTF-8, optional initial UTF-8 BOM; reject binary control characters and malformed/other encodings. No PDF, RTF, image or OCR parsing. |
| Input/evidence | At most 16,384 bytes per whole file. Reject oversize rather than accept a prefix. A growth-detection read can observe one extra sentinel byte. No truncated text is accepted. |
| Aggregate | 65,536 bytes actually read per task, plus at most one rejection sentinel byte. Files whose preflight size exceeds the remaining budget stay unopened. Four full-size files exhaust it. |
| Working buffer | 4,096 bytes; evidence processed serially, not retained for every file. Only proposed names and safe reasons survive each naming iteration. |
| Read deadline | Cooperative one-second per-file preflight/read deadline, with five seconds cumulative measured preflight/read time across the task. Metadata queries count toward this elapsed time. |
| Processing deadline | Cooperative 45-second content-stage deadline including naming completions; late replies are discarded, remaining files abstain. Earlier intent generation and executor work are outside this clock. |
| Model limits | Existing native 8,192 prompt-plus-output context and 2,048 overall output ceiling remain; naming requests 512 output tokens and accepts at most 8,192 response bytes. UI adapter maps native context/output limits to `PlanningError.requestTooLarge`, yielding safe model-limit abstention in the content stage. |

**None of these elapsed-time checks interrupts a blocked system call or native
model completion.** `openat`, provider metadata and `read` remain synchronous;
`O_NONBLOCK` is not a regular-file I/O deadline. Checks before/after work prevent
subsequent work and accepting late evidence, not the blocking call itself. A
supervised, killable inspection helper and minimum-hardware latency/memory tests
remain necessary before claiming stronger containment or the #1 100-file/60-second
target. No fake timeout race or abandoned detached worker was introduced.

Content authorization is separate from #8 traversal eligibility. Reads require
the selected root, valid captured ancestor authority, matching file snapshot and
regular single-link local file. Provider/dataless/downloading and alias state is
checked before opening. Parent directories are pinned one component at a time;
the final leaf is opened with `O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC`.
Parent/ancestor identities and source snapshots are checked around provider
metadata, before opening, around bounded reads and before accepting evidence.
No slash-containing path is passed directly to the content `openat` call.
All descriptors close with `defer`. Foundation provider queries still use URLs,
not descriptors; real provider race/nonhydration qualification remains open.

Recursive rename-only destinations retain the original relative parent.
`PlannedChange.ancestorIdentities` copies the inventory's authority, never invented
ancestry. Existing executor validation, whole-plan collisions, exclusive moves,
101-file confirmation, source rechecks, partial cancellation and newest-first
durable undo remain the only mutation path.

## Privacy and downstream interfaces

- `InspectionEvidence(kind:text:coverage:)` is transient, not Codable, and never
  enters the journal, logs, caches, diagnostics or an error. Prompt JSON is used
  only by the local completion adapter. Runtime errors after inspection are
  reduced to fixed safe errors; arbitrary model error descriptions cannot escape.
- History retains the existing ordinary operation paths/names and identities,
  not evidence titles/excerpts or requests. Resulting filenames necessarily remain
  in undo history. Swift value copies, OS swap and crash behavior are not a secure
  erasure promise. No temporary extracted text/image files are created.
- **#10/#11:** `inspectContents(_:root:budget:) -> InspectionEvidence` is the
  format-dispatch seam. `readInspectionInput(_:root:budget:maximumBytes:)` supplies
  bounded bytes only after the shared snapshot/ancestor/cloud preflight. New
  adapters must authorize a format before opening, add parser/helper containment,
  page/pixel/output budgets and honest coverage, then return transient evidence to
  the same `resolveContentNames`/validation/plan expansion path. Do not merely add
  `.pdf` to the UTF-8 extension list. PDF/OCR are deliberately not implemented.
- **#14:** public `InspectionCode` and optional
  `FileOutcome.inspectionCode` expose only allowlisted categories: `unsupported`,
  `unavailable`, `changed`, `inputLimit`, `taskLimit`, `modelLimit`, `unreadable`,
  `insufficient`, `deadline`. Diagnostics may count codes. Do not serialize the
  containing outcome (it includes an ordinary filename), its explanation, model
  errors, prompts or `InspectionEvidence`. There is no diagnostic exporter here.

## Coordinator red → green and native evidence

All tests use the agreed coordinator seam, actual temporary files/bookmarks,
controlled model completions, filesystem outcomes, history and undo. Observed
red → green includes content refusal → real evidence naming; lost original
date/identifier/name rejection; source-language instruction laundering rejection;
explicit grounded descriptor translation; selection before reads; sort-only
content-authority rejection; strict naming shape/ID preservation; one valid
naming replacement; composed noncontiguous titles with preserved tokens; short
source-language fallback; model-context abstention; and `AB123` versus `AB1234`.

After #8 integration, an unchanged file inode/snapshot under a **replaced ancestor**
was incorrectly read. A real nested-directory swap fixture went red; captured
ancestor validation and pinned parent/leaf reads made it green. Normal nested
renaming retains its parent and supports reopened undo; replaced links/ancestors
abstain without reading outside content or mutating files.

Additional cases cover whole-file size boundary/BOM, invalid UTF-8, empty and
unsupported files, aggregate exhaustion, readable-name unchanged versus
abstention, global collisions, cancellation during content inference, edited
sources after evidence, safe reduction of private model errors, and persisted
history marker checks. Existing metadata, recursive, executor, confirmation,
recovery, model lifecycle and undo suites are retained.

The signed native diagnostic reuses the existing approved candidate under
`~/Library/Application Support/Tidy/QualificationModels`; no redownload. It runs
with network denied and original SwiftPM-product reads denied. Early complete
smoke runs failed safely on schema/coverage, title quotation and missing IDs;
these are failed runs, not passed gates. A direct English/Spanish content run
then passed two changes, protected names/IDs/dates, original bytes and reopened
undo in 9.278 seconds. Integrated recursive naming also exposed a source-prose
capitalization mismatch, now covered red → green without relaxing exact protected
tokens. A subsequent full integrated smoke passed English plus nested Spanish
content naming in 7.918 seconds, followed by all metadata/recursive/runtime checks.

Host: Apple M4 Max, 36 GiB, macOS 27.0.1 (not qualification on macOS 14).
Candidate: `mlx-community/Qwen3-4B-Instruct-2507-4bit`, immutable revision
`50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b`; MLX Swift LM 3.32.3,
MLX Swift 0.32.3, Transformers 1.3.5. Only synthetic non-sensitive fixtures were
used; raw prompts/replies/extracted text were never logged. Temporary fixed-code
and boolean/counter qualification logging was removed before final checks.
An additional final rerun rejected a response after the earlier full pass;
input serialization now uses sorted keys, consistent with metadata planning.
This is not treated as broad reliability qualification or permission to relax
evidence validation. All complete-run failures remain failed qualification runs.

## Final checks and remaining gates

| Command | Result |
| --- | --- |
| `swift test --disable-automatic-resolution` | Passed: 82 executed core tests and 11 model tests, **93 executed total**; one existing real File Provider fixture skipped (83 reported core tests). Includes 15 content test functions with parameterized cases. |
| `bash scripts/lint.sh` | Passed strict formatting, three plists and shell syntax. |
| `git diff --check` | Passed. |
| `env NSUnbufferedIO=YES bash scripts/model-smoke.sh` | Final sorted-input complete run passed: English plus nested Spanish evidence naming, reopened undo, existing metadata task chains, recursive sort, context rejection, cancellation and model replacement; network denied, no download. |
| `bash scripts/build-app.sh` | Passed arm64 packaging, bundled Metal resources, ad-hoc signing and strict signature verification; no GUI interaction. |

Approved locked dependencies were fetched from cache during the first build;
no approval blocker occurred. The existing upstream MLX resource-bundle
mutated-node warning remains nonfatal. No native GUI was launched/interacted with.

Final complete smoke: verified load 1.905 s; two-file English/nested-Spanish
content task plus execution/reopened undo 8.090 s; last naming completion
436 prompt / 58 output tokens, 0.219 s prefill / 1.226 s generation. Existing
combined metadata task 5.844 s; recursive type sort 3.824 s; native cancellation
quiesced in 0.065 s. These tiny fixtures are not the representative-corpus gate.
No raw prompt/reply logging remains in production code.

Native GUI tools are unavailable: picker/write consent, visible disclosure,
clarification/confirmation presentation, progress/cancel responsiveness,
keyboard/VoiceOver, final sandbox app behavior and actual process-restart UI
still need manual verification. Recreating the coordinator is not restarting
the app. Real File Provider fixtures, macOS 14, lower-memory/minimum hardware,
blocked-I/O termination, broader languages/requests, extraction race stress,
semantic naming quality/90% usefulness/80% cryptic coverage and the 100-file
performance target remain open. No acceptance or release gate is silently closed.
