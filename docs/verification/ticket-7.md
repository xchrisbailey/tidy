# #7 — offline natural-language metadata tasks

2026-10-28. Provisional native release gates remain open; no ticket was closed.
Started at the requested clean `1f5a202` on `ticket/7-natural-language`. The first
implementation through `85e0194` integrated execution but restricted language to
two sentence patterns. **The completeness follow-up replaces that allowlist**
with model-resolved, validated metadata intent and combined rules.

No dependencies, model downloads, cloud inference, CI or primary user docs were
added. The approved pinned graph and existing qualification artifact are reused.

## One public task interface

`TaskCoordinator.planTask(request:model:) async throws -> TaskPlanningOutcome`
still accepts `PlanCompletion` (Sendable async system/user strings plus output
token limit) and returns an immutable `SortPlan`, clarification or whole-request
refusal. Production calls `ModelServices.shared.runtime.completeJSON` directly.
Startup uses the existing `ModelSetup.restore()`; active `state` determines
readiness. Model selection/setup/storage remain separate from the primary task.

The local model interprets the user's entire request into a bounded rule program
and a decision for **every** eligible source ID. It is no longer asked merely to
copy a predetermined type sort. Metadata consists of names, sizes and modification
dates, JSON-encoded separately from the user's request. No file contents are read
for planning; names never supply instruction authority.

### Supported interpreted rules

| Area | Bounded rules |
| --- | --- |
| Sorting | Type; filename year/month; modification year/month in UTC; one immediate child folder named by an exact quoted user literal; or no move. |
| Naming | Ordered case conversion (lower/upper/title), space/underscore/hyphen replacement, exact quoted prefix/suffix, filename-date prefix or modification-date prefix. Up to four rules can be combined with sorting. |
| Selection | Explicit extensions and/or an exact quoted name substring. All candidates still have source-ID coverage; excluded files are unchanged with an `outsideRequest` reason. |
| Uncertainty | Whole-task clarification/refusal, or per-file abstention without applying a partial subset of that file's combined rules. Missing, invalid or conflicting filename dates are not guessed. |

Year/month folder labels are `YYYY` / `YYYY-MM`; date prefixes are `YYYY-MM-DD`.
Filename extraction recognizes unambiguous Gregorian `YYYY`, `YYYY-MM`,
`YYYY-MM-DD` and compact equivalents (years 1900–2199). Modification dates come
from actual inventory snapshots and use UTC. Extensions retain exact bytes.
Known date spellings (including non-ISO numeric dates), UUIDs and digit-bearing
identifiers are protected during case/separator changes. Recognizable original
words are transformed or supplemented, never replaced by a fabricated basename.

Natural-language phrasing is interpreted by the model; it is not matched against
a complete-sentence English allowlist. The finite rule set is intentional: it
does not provide arbitrary code, arbitrary name generation, contents-based facts,
existing-folder restructuring, deletion/copying/transmission or recursive source
access. Unsupported formats/layouts or unclear rules require resubmission rather
than silent substitution. Bare date sorting asks for filename versus modification
source and year/month precision before inference can guess.

## Authorization is not JSON validity

The complete envelope has exactly `status`, `message`, `clauses`, `sort`, `rename`,
`selection`, `files`. Every nested field has an exact shape. Unknown/duplicate
JSON keys, invented/duplicate/missing source IDs, unsupported rule kinds,
dispositions or raw operation paths are rejected. `files` contains only actual
source IDs with `apply`/`abstain`; the model cannot supply free destinations or
rename operations. The app expands validated rules against actual captured file
snapshots into the complete immutable executor plan.

The interpretation must account for every request word in order. Presentation
case, quotes, whitespace and prose punctuation are not treated as permission;
literal values are separately checked **exactly against quoted original user
text**, including literal case and spaces. Each action needs positive request
evidence for its rule, action class, date source and precision or literal value.
Evidence cannot come from a filename, quoted selector text, invented wording or
negated action. Sort evidence cannot authorize renaming; rename-only requests
cannot authorize moving. Preservation constraints do not become positive requests
to edit contents or delete files.

The model must classify any unsupported/ambiguous clause as such for the whole
request. Before inference, a separate policy check declines known destructive/
transmitting/mixed requests rather than allowing the model to drop those actions.
Quoted naming literals and explicit preservation/negative constraints are
distinguished from positive actions. Other unsupported intents are resolved by
the structured model response (including a controlled mixed sorting/translation
refusal). Whole-request refusals offer a supported metadata-only resubmission,
never silently execute the supported part.

This is bounded semantic interpretation with validation, **not a claim that JSON
syntax or an LLM's label proves arbitrary natural-language intent**. The model's
interpretation/classification still needs corpus qualification. Independent
checks prevent invented operations, ungrounded rule parameters, unauthorized
action classes, information loss and access beyond the selected grant.

### Filesystem and retry restrictions

- Source names are actual eligible direct children, never slash-containing model
  paths. Destination folders are either the root sentinel `.` or a validated
  nonhidden **single component**, not arbitrary paths. The journal's fixed type
  allowlist is replaced only by that shared component validator; traversal,
  separators, control characters and hidden folder targets remain forbidden.
- Existing destination folders are opened relative to the pinned root, no-follow,
  and identity checked. Existing packages/aliases/dataless directories are refused;
  source folders are never moved or traversed. Existing/planned case variants are
  reserved before mutation, with predictable extension-preserving collision
  suffixes and original proposed-name priority.
- The existing executor revalidates the whole destination plan before any move
  and every source snapshot immediately before its operation. Exclusive rename,
  durable intent/completion, recovery, best-effort task/file undo and newest-first
  identity precedence remain in use. No journal recovery core was duplicated.
- There are **at most two completions total**, not a repair loop per stage:
  initial structured interpretation/complete plan and one complete replacement.
  Replacement feedback is a fixed validation-category correction, never raw
  untrusted model output. Invalid replacement changes nothing. Runtime failure or
  cancellation propagates without retrying/truncating its output.
- Both calls request at most 2,048 output tokens. Native 8,192 prompt-plus-output
  and 2,048 output hard limits remain unchanged. No chunking, prefix acceptance or
  cloud fallback. Oversized tasks are honestly rejected and the native UI asks
  for narrower scope. The 1,000-file executor ceiling is not a model-fit promise.
- Existing immediate execution, 100/101-file confirmation counts, progress,
  cancellation, persistent grouped history and undo are retained. Results
  distinguish changed, already organized, outside-selection unchanged, abstained,
  skipped, failed and unprocessed outcomes. Busy exclusion spans inference.

## Agreed-seam red → green and controlled evidence

All tests cross `TaskCoordinator` with actual temporary files/bookmarks and only
the model-completion seam controlled. Existing inventory/execution/recovery/model
setup suites are retained. The earlier two-rule coordinator tests were migrated
to the new structured response protocol, not replaced with private-method tests.

Observed follow-up red → green:

1. A natural date-sort + separator request was refused by the old sentence
   allowlist; model-interpreted filename-month sorting and combined naming now
   execute into a real date folder and undo after reopening.
2. PDF selection embedded in a sorting clause was rejected. Combined typed clause
   effects now preserve full request coverage while applying actual UTC
   modification-month/date-prefix rules only to the requested extension.
3. A UUID's all-letter segment and a Unicode identifier were lowercased; protection
   now preserves both, including Unicode combining marks. A filename date parser
   incorrectly accepted digits embedded in a non-Latin identifier; Unicode word
   boundaries now abstain instead. A non-ISO date's underscores were replaced;
   date protection now leaves that complete date spelling intact.
4. A negated lowercase instruction was accepted as rename permission; positive
   evidence/negation checks now reject it before mutation. An ordinary noun in
   “prefix file names” was also incorrectly sufficient for a proposed folder move;
   action evidence now requires unquoted sorting/moving verbs, including normal
   inflections such as “sorted,” rather than the noun “file.”
5. A request to run a type sort while keeping contents unchanged and never
   deleting was incorrectly refused as a positive unsupported request. Separating
   negative/preservation constraints from positive actions made it pass.
6. Bare date sorting previously reached inference twice and failed; it now asks
   the source/precision question without guessing or mutating.
7. The real model normalized prose quotes/commas while retaining every request
   word. A controlled test reproduced rejection. Word-complete prose coverage
   now accepts harmless presentation differences, while a separate adversarial
   literal-whitespace test still rejects changing a quoted prefix's actual value.

Additional coverage includes missing/invented/duplicate IDs, duplicate/unknown
keys, malformed/truncated JSON, delete dispositions, raw traversal fields,
invented literals, omitted unsupported clauses, instruction-like filenames,
sort-versus-rename authority, valid replacement and exactly one invalid
replacement, ambiguity, mixed unsupported refusal, protected identifiers/dates/
extensions, precise multi-rule naming, deterministic collisions, unknown/invalid/
conflicting dates, skipped versus abstained versus unchanged, custom-folder
symlinks/packages, late destination conflicts, 101-file confirmation/cancellation,
inference cancellation/busy exclusion, and model rename→sort chains requiring
newest-first undo after coordinator recreation.

## Real native offline qualification

`bash scripts/model-smoke.sh` builds with approved locked dependency resolution
allowed, then runs a signed diagnostic `.app` with `(deny network*)` and reads of
the original SwiftPM product directory denied. It reuses the existing approved
artifact in `~/Library/Application Support/Tidy/QualificationModels`; no download.
Only non-sensitive synthetic fixtures are used. No raw prompts/model responses or
real user filenames are logged; temporary diagnostic category logging is removed.

The diagnostic uses the bookmark entitlement and a resolved scoped bookmark for
its own fixture. Production access checks are not bypassed. This exercises the
public coordinator, native MLX and packaged Metal resources, **not** NSOpenPanel
or the final app's interactive sandbox consent flow.

Successful observed stages include:

- Type sorting with an adversarial instruction-like filename treated as data:
  two changes, one unknown-type abstention, original bytes restored by reopened
  undo.
- Real-model rename followed by real-model sorting; older undo blocked until the
  newer task was undone, then original names/bytes restored after reopening.
- Real-model filename-month sorting combined with lowercase, underscores and an
  exact quoted prefix: one rename+move, two date-unknown abstentions; exact date,
  identifier and extension retained; date-folder undo after reopening passed.
- A real oversized 303-file metadata prompt rejected at the native context bound,
  without a partial plan or mutations. Existing native generation cancellation,
  post-cancellation inference and transactional model-replacement checks remain.

Early native checks exposed misleading schema examples and punctuation-only
coverage failures; these were **failed complete smoke runs**, not passing gates.
Balanced valid examples, bounded validation feedback and literal-safe prose
coverage corrected those issues. Final full-command results are recorded below.

## Remaining native gates and downstream interface

Native GUI tools are unavailable. Picker/write consent, clarification editing and
resubmission, automatic installed-model restore on app relaunch, confirmation
cancel, progress/cancel responsiveness, keyboard/VoiceOver, per-file presentation,
history windows and final app sandbox behavior still need manual qualification.
Coordinator recreation is not an actual native app process restart.

Broader natural-language/adversarial planning quality, output exhaustion,
full-context/pressure behavior, supported filesystems, macOS 14, lower-memory
hardware and final distribution/archive execution remain qualification gates.
Unsupported date formats, naming transformations and nested layouts are explained
or clarified, never silently approximated.

- #8: the public task interface and completion adapter remain compatible. Source
  IDs and pinned-directory expansion are **direct-child only**. Extend source and
  destination handle authority together before supporting recursion/nested paths;
  do not weaken the single-component journal check.
- #9: reuse `PlanCompletion` and the local runtime, but content naming needs
  separately authorized reads, evidence/snapshot binding and preservation
  validation. Neither arbitrary generated names nor content-read permission are
  implied by this metadata rule program.

## Final integrated checks

The branch retains the prior #12/#5 merges and was checked against the latest
integration tip `b319032` before final reporting (`git merge --no-edit
integration/tidy-v1`: already up to date). The public setup/runtime lifecycle and
recovery core were reused, not duplicated.

| Command | Result |
| --- | --- |
| `swift test --disable-automatic-resolution` | Passed: 58 executed core tests plus 11 model tests, **69 executed total**; one existing native File Provider fixture skipped (59 reported core tests). |
| `bash scripts/lint.sh` | Passed strict Swift formatting, all three plists and shell syntax. |
| `git diff --check` | Passed. |
| `bash scripts/model-smoke.sh` | Passed the complete signed diagnostic run with network and original-product reads denied; no download or automatic transmission. |
| `bash scripts/build-app.sh` | Passed arm64 app packaging, bundled Metal-resource check, ad-hoc signing and strict signature verification. App not launched/interacted with. |

Final complete native smoke measurements on the existing M4 Max / 36 GB host:

- Verified local load/readiness: 2.065 s.
- Type metadata task including reopened undo: 3.560 s; 1,209 prompt / 171 output
  tokens, 0.971 s prefill / 3.465 s generation.
- Combined filename-month + lowercase/separator/quoted-prefix task including
  reopened undo: 5.550 s; 1,230 prompt / 302 output tokens, 1.059 s prefill /
  5.492 s generation. Exactly one renamed/moved file; two files abstained for
  missing dates. Original date/identifier/extension and bytes verified in memory.
- Model rename→sort chain/newest-first reopened undo passed. Bare date ambiguity
  and known mixed unsupported requests were safely resolved by task policy before
  inference (not claimed as successful model interpretation of those requests).
- Oversized actual metadata input hit the native context bound with no mutations;
  native cancellation drained in 0.039 s, then inference and #12 replacement
  checks passed. No larger output budget or prefix acceptance was introduced.

Dependency resolution was allowed while building; only the actual diagnostic
task process denied network access. No approval blocker occurred. The existing
upstream MLX resource-bundle mutated-node warning remains nonfatal. No GUI or
broader release-quality gate is claimed complete by these results.
