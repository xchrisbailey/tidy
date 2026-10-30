# Selection authority follow-up

2026-10-29. Follow-up to the focused spec review at `5ab6900`. The earlier
[integration review verification](integration-review-fixes.md) remains unchanged;
its signed candidate is superseded by this correction. **No public release;
supported hardware remains NONE qualified.**

## Defect and correction

The Phase 1 guard incorrectly treated every extension mention as selection.
`Sort all files by type and keep PDF filenames unchanged` therefore rejected a
correct empty-selection plan, while a PDF-only replacement could pass and omit
TXT files from the requested all-files sort.

Selection is now derived from independently recognized positive action clauses,
not the model's effect labels or preservation clauses. Quoted literals do not
introduce action boundaries. Supplied extensions/name filters must exactly match
the bound scope, including the empty/all-files case. An unqualified continuation
can inherit its preceding scope; an explicit different scope cannot become a
global union or subset. The single-selection schema requires clarification or
rejection when action-specific scopes differ. Supported case-action spellings
remain separate action boundaries.

Preservation is checked against the independently bound scope: unchanged names
are redundant for sorting, unchanged contents are redundant for both operations,
and an explicitly disjoint extension is untouched. An overlapping naming/location
exception that the plan cannot honor is rejected, not turned into positive
selection authority. The original PDF-only content omission/private-marker tests
remain enabled. No inventory-driven fallback or unrelated-file inspection was
introduced.

## Public-seam regression evidence

The exact PDF+TXT fixture and complete controlled intents establish:

- Correct empty selection plans both files on the first response, with either a
  second correct response or the formerly forced PDF-only response queued but
  never requested. Execution preserves names/bytes; reopened task undo restores
  both originals.
- The narrowed whole-request `sort+selection`, `extensions:[pdf]`, evidence `PDF`,
  `files:all` response rejects without mutation, even on replacement.
- All-files sort plus PDF content naming, its reverse action order, and PDF sort
  plus TXT naming cannot become a global subset/union or inspect unrelated text.
- Lowercase/lower case/lower-case aliases retain separate action scopes.
- `and keep`, `keeping` and `while keeping` preservation wording cannot narrow
  the all-files action.
- Unrecognized preservation phrasing such as `Sort files by type with PDF
  filenames unchanged` fails closed rather than accepting a PDF-only subset.
- TXT+quoted-name selection repairs omission without swallowing a PDF-name
  preservation constraint; preserving a provably disjoint type remains supported.

Each defect slice was observed failing before its implementation. The first draft
of the all-files regression had an invalid helper-generated envelope; it was
corrected to a complete literal intent, then the original scan was reinstated
temporarily to establish the valid failing case before restoring the correction.
No private-helper tests, relaxed assertions, global threshold changes, new
dependencies, model downloads, CI or primary user-documentation edits.

Logs under the approved OpenCode temporary directory are prefixed
`selection-followup-`: `valid-all-red`, `all-green`, `narrow-red`, `narrow-green`,
`mixed-red`, `mixed-green`, `alias-red`, `alias-green`, `disjoint-red`,
`disjoint-green`, `gerund-red`, `gerund-green`,
`ambiguous-preservation-red`, plus full-check logs below (all `.log`).

## Checks

Workdir: `/Users/chris/dev/utils/tidy-review-fixes`, based on integrated `5ab6900`.
Checks run against the finalized source tree, before its commit; hosted build
metadata retains that base HEAD and the dirty-source list. No candidate app was
rebuilt, packaged or signed. The explicitly requested hosted optimized check
creates/signs only its unqualified test host through the existing script.

```sh
swift test --disable-automatic-resolution
bash scripts/release-tests.sh
bash scripts/lint.sh
git diff --check
git diff --exit-code 5ab6900 -- Sources/TidyModelSmoke/QualificationCorpus.json Sources/TidyModelSmoke/Qualification.swift docs/verification/qualification-v1-rubric.md Package.swift Package.resolved
```

Full debug: PASS, 117 core tests/14 suites (16.715 s), 12 model tests/two suites
(1.377 s), two inspection-supervisor tests (0.368 s). Parameterized cases are
additional to these test-function counts. Log:
`selection-followup-debug-complete.log`. Strict Swift formatting, plist/shell
lint and whitespace checks pass. Corpus, rubric, qualification requests, package
and lockfile comparison to `5ab6900` is clean.

Proper optimized hosted check: PASS, **all 117 discovered core test functions**
in 14 suites (30.798 s), then 12 normal optimized model tests (1.367 s) and two
inspection-supervisor tests (0.444 s). Discovery comparison and Developer ID
hardened-runtime host/XPC/parser signature checks passed through the unchanged
`scripts/release-tests.sh`. Host artifacts:
`.build/release-tests/host.qBiX83`; log:
`selection-followup-optimized-complete.log`. This test host is not the candidate
app or evidence of native App Sandbox picker grants. Earlier intermediate
passing debug/hosted logs are retained separately; the `complete` logs above
cover the final source and all preservation variants.

## Native attempt and remaining gates

Added `TidyModelSmoke --selection-authority-only` to exercise the exact request
against the existing actual model and verify both moves, unchanged names/bytes
and reopened undo after the next authorized diagnostic rebuild.

The current-source direct CLI attempt ran with network denied and reached verified
model readiness, but failed **before the task request** creating its scoped
bookmark: `Required entitlement com.apple.security.files.bookmarks.app-scope is
missing or false`. This is a failed/blocked native request check, not a passing
model-authority result. Log: `selection-followup-native.log`. No retry with weakened
grants, signing or product packaging was performed. Existing signed diagnostics
contain the old validator and are not evidence for this fix.

The 32-fixture corpus, rubric, thresholds, model and qualification requests were
not retuned. Corpus naming uses the unchanged single generic content-naming
request; metadata performance uses a single generic sort request. No new native
32-case/performance score is claimed: executing the current diagnostic needs the
same missing entitlement. Previous-tip accuracy/timing remain previous-tip
measurements, not current-source qualification. Rebuild/run the signed diagnostic
and candidate only when authorized after this fix.

Native GUI/cancellation accessibility, real picker grants/provider behavior,
minimum hardware/macOS, pressure behavior, independent human scoring and release
clearance remain open. No manual or hardware qualification is implied.
