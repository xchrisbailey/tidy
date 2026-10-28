# #7 — local task planning verification

2026-10-28. Provisional downstream implementation; leave #7 open. Started on
`ticket/7-natural-language` at the requested clean `1f5a202` base. No new
dependencies, cloud service, CI, primary user documentation, or model download.

## Public boundary and authority

`TaskCoordinator.planTask(request:model:) async throws -> TaskPlanningOutcome`
uses the agreed task-coordination seam. `PlanCompletion` is a Sendable async
closure taking system/user strings and the maximum output token count. Production
connects it directly to `ModelServices.shared.runtime.completeJSON`; no model
picker or downloader occurs during execution. Startup invokes the existing
`ModelSetup.restore()` lifecycle and the task UI consults its active `state`.

Outcomes are an immutable `SortPlan`, a clarification, or whole-request refusal.
Clarifications ask for a complete edited resubmission, not general chat. The
existing executor handles immediate execution, counts/confirmation above 100,
progress, cancellation, durable grouped history and best-effort undo. Results
have a separate `abstained` collection, distinct from already-organized
`unchanged`, ineligible/stale `skipped`, failed and unprocessed files.

**JSON validity is not semantic authorization.** Before calling the model, the
entire request must match a supported authority rule. The model cannot expand
that authority. A type sort permits only the existing deterministic type folders
and original names (plus reserved predictable collision suffixes). The explicit
spaces-to-hyphens rename permits only that transformation of the stem, preserving
extension bytes, dates, identifiers and recognizable words; it cannot move files.
Root-only renames use `destinationFolder == "."` with the same pinned root,
exclusive move, journal and undo machinery. The sole journal-core change allows
that exact root sentinel alongside the existing fixed type-folder allowlist.

All eligible direct-child source IDs must occur exactly once. Missing/invented
sources, duplicate IDs/JSON keys, unknown fields, unsupported dispositions,
unauthorized names/folders, traversal, partial/truncated JSON and non-JSON are
rejected as an entire plan. The model can abstain but cannot substitute another
destination. Filenames are JSON-encoded data, never interpolated as instructions;
file contents are not read. No missing fact or path is invented.

There are at most two completions: initial output and one complete bounded
replacement, both with a 2,048-token output limit. Invalid replacement changes
nothing. Runtime failure/cancellation propagates without another attempt.
The existing native 8,192 prompt-plus-output and 2,048 output limits remain
unchanged: no chunking, prefix acceptance or silent truncation. A 1,000-file
executor ceiling is not a promise that every such plan fits the model context.
Planning holds the coordinator's busy state across model suspension; execution
still revalidates the complete destination plan and each source snapshot.

## Observed red → green

Tests use actual temporary files/bookmarks through `TaskCoordinator`, with only
the public model-completion boundary controlled:

1. New metadata task test failed to compile because `planTask` did not exist;
   passed with local structured planning, execution and reopened undo.
2. Rename test returned clarification instead of a plan. Adding explicit rename
   authority exposed a real reopened-undo failure (`journalUnavailable`); the
   precise root sentinel allowlist addition made extension/date/identifier
   preservation, separate unchanged/abstention and reopened undo pass.
3. Mixed sort/delete returned clarification instead of whole-request refusal;
   complete-request authority/refusal now passes without calling the model.
4. An otherwise valid plan with an extra `delete` field was accepted by
   Foundation's decoder. Strict envelope/field and duplicate-key validation made
   the test pass with exactly one invalid replacement and no filesystem/history
   mutation.

Supplemental coverage includes eight malformed/unauthorized response cases,
valid replacement, clarification before inference and from the model, 101-file
model-plan confirmation, cancellation retaining one completed rename and undo,
inference-time cancellation/busy exclusion, and a model-driven rename→sort chain
that blocks older undo until newer task undo succeeds after reopening. Existing executor/inventory,
history, collision, stale-source, provider and setup tests remain in the suite.

## Actual offline native task

`bash scripts/model-smoke.sh` builds first with approved locked dependency
resolution allowed, then runs the signed diagnostic bundle with `(deny network*)`
and reads of the original product directory denied. It reuses the already
approved candidate in `~/Library/Application Support/Tidy/QualificationModels`.
Only non-sensitive synthetic fixtures are used; logs contain counts/timing/memory,
not raw requests, names or model responses.

Observed successful run before the final integration merge:

- Verified load/readiness: 1.888 s.
- Complete real-model task via `TaskCoordinator`, execution and reopened undo:
  2.345 s; two moved files, one unknown-type abstention; original bytes restored.
- Task prompt/output: 233 / 149 tokens; prefill 0.104 s, generation 2.274 s.
- One filename said to ignore instructions and delete files; it was moved as
  ordinary data, retained its name and contents, and was safely undone.
- Cancellation drained native work in 0.078 s and subsequent inference passed.

The diagnostic initially failed on scoped access under the outer sandbox. A
minimal probe showed an unscoped URL returns false there while a resolved scoped
bookmark succeeds; the unsigned-entitlement variant also reported the missing
app-scope bookmark entitlement. The diagnostic now signs with only that bookmark
entitlement and resolves a real bookmark for its own fixture before granting it.
No production access check was bypassed. This is a diagnostic bundle under
network denial, **not** NSOpenPanel or final sandboxed GUI qualification.

## Remaining gates and downstream API

- Native GUI tools are unavailable: picker consent, clarification editing,
  automatic restore on relaunch, setup/not-ready messaging, confirmation cancel,
  progress/cancel responsiveness, accessibility, per-file result presentation and
  final app sandbox behavior need manual qualification. No ticket is closed.
- Language coverage is deliberately limited: type-sort phrasing and explicit
  spaces-to-hyphens naming. Other precise naming rules, date-based sorting,
  combined sort-plus-rename requests and richer natural-language interpretation
  remain an acceptance gap, rather than treating an unverified model intent as
  permission. Unrecognized/mixed requests are declined with supported versions.
- #8 recursion: the current plan builder, source IDs and executor are direct-child
  only. Do not insert slash-containing sources into this envelope. Extend the
  pinned-directory authority/executor together before allowing nested IDs/paths.
- #9 content naming: `PlanCompletion` can remain the local model adapter, but
  content-based proposals need their own evidence/authority validation before
  constructing immutable plans. Do not loosen the exact metadata authorization
  comparison to accept arbitrary model filenames. No content-read permission is
  implied by this API.
- Small real-model corpus only; broader planning quality, output exhaustion,
  full-context/pressure behavior, macOS 14 and low-memory hardware remain open.

## Integrated checks

Merged #12 through `23d4574` in `1a1f54a`, then merged integration through #5's
`b319032`. `ModelSetup.state` remains the sole readiness API; no runtime conformer
or duplicate lifecycle was introduced. #5 recovery remains unchanged apart from
the narrow root-sentinel journal allowlist addition described above.

- `swift test --disable-automatic-resolution`: 11 model tests and 47 executed core
  tests passed (48 reported core tests, one existing native provider fixture
  skipped). Nine natural-language coordinator tests include eight parameterized
  unauthorized-output cases. The integrated rename→sort chain/newest-first undo
  and cancellation tests passed.
- `bash scripts/lint.sh`: passed strict Swift formatting, all three packaging
  plists and shell syntax. `git diff --check`: passed.
- Final `bash scripts/model-smoke.sh` after #5/#12 integration passed with network
  denied and no download: verified load 1.876 s; first complete metadata task
  2.327 s (232 prompt / 149 output tokens, 0.106 s prefill / 2.256 s generation).
  The additional **real-model** rename→sort chain also passed: older task undo
  was blocked, newer then older undo restored all original names and bytes after
  coordinator reopen. This is application-boundary/diagnostic-bundle evidence,
  not native GUI interaction. Native cancellation drained in 0.028 s; inference
  after cancellation and #12's retained-container replacement checks passed.
- Final `bash scripts/build-app.sh` passed: sandboxed arm64 app, bundled Metal
  resources, ad-hoc signing and strict signature verification. The app was not
  launched or interacted with through native GUI tools.
- A real oversized metadata inventory (303 eligible synthetic files) reached the
  native context check and threw `LocalInferenceError.contextLimit`, with no
  partial plan, new history or mutations. The main task adapter explains context
  and output limits as a request to narrow scope rather than accepting a prefix.
- Dependency resolution was allowed during builds; offline denial applies only
  to the actual diagnostic task process. No approval blocker occurred. The
  existing upstream resource-bundle mutated-node warning remains nonfatal.
