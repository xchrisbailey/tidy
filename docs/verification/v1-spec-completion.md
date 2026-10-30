# V1 executable-spec follow-up

2026-10-30. Owner requested finishing implementation against milestone
[#1](https://github.com/xchrisbailey/tidy/issues/1) after tracker reconciliation.
The implementation follow-up is
[#19](https://github.com/xchrisbailey/tidy/issues/19); code commits `a4497b0` and
`7c56b0d`, based
on approved workspace `53aeb2f`. Closing previous implementation slices was not
treated as proof of complete spec conformance.

## Reproduced gaps and corrections

| Spec obligation | Reproduced behavior | Correction |
| --- | --- | --- |
| A later attempt inspects afresh | A new/corrected request omitted new arrivals and stale-skipped edited files after selection, clarification or refusal. A corrupt read bookmark could still reach inference using the old inventory. | Restore the selected read grant and inventory before every new workspace submission; failure stops planning and invalidates the displayed snapshot. Confirmation still executes its captured plan without replanning. |
| Recheck folder identity before mutation | Undo moved a file through a pinned descriptor after the selected root's original path was replaced at `undoIntentSaved`. | Check root path/identity before undo and again at its final mutation boundary. Folder cleanup also checks identity, including after `undoCompletionSaved`. |
| Validate requested rename meaning | A model reversed separator source/target while quoting the complete correct request, and the opposite transformation executed. | Validate direction in supported replacement constructions, including substitute/use wording and quoted separator characters. Ambiguous wording and action text inside nonseparator quoted literals cannot authorize a transformation. |
| Explicit requested filename language wins | A model omitted the requested English parameter and naming fell back to Spanish evidence. | Independently recognize named output languages; reject omitted/mismatched parameters before inspection. Unsupported named languages require a corrected clarification/refusal rather than a silent source-language fallback. Descriptor translation remains limited to the existing six supported languages. |
| Refuse the entire mixed unsupported request | A model quoted the full request but declared only sorting, hiding a request to translate document contents. | Preflight rejects document translation even inside a supported clause. Filename translation based on contents and negative preservation constraints remain distinct. |

These are narrow guards at existing boundaries, not a new inference architecture,
general translation feature or additional model replacement allowance. The single
shared correction budget, complete-plan validation, local-only processing, durable
history and no-overwrite policies remain unchanged.

## Verification

- Baseline debug: 117 coordinator, 13 model, 2 worker, 16 workspace functions passed.
- Before production changes, the focused six-function invocation failed on all five
  original defect paths. Local log: `.build/v1-gap-red.log`.
- Additional quoted-separator and unsupported-language cases also failed before
  their corrections: `.build/v1-gap-edge-red.log`.
- Final debug at `a4497b0`: 123 coordinator, 13 model, 2 worker and 18 workspace
  functions passed, with additional parameterized cases. Local log:
  `.build/v1-spec-debug-tests.log`.
- Independent Standards/Spec review found additional language/translation cases:
  coordinated output languages could be dropped, valid filename translation with
  a report-evidence modifier or later sorting could be refused, and coordinated
  file-text translation could still be omitted. Each reproduced red in
  `.build/v1-review-red.log`; fixes in `7c56b0d` pass
  `.build/v1-review-green.log`. Final full debug at `7c56b0d` passes the same 156
  functions with expanded parameterized cases:
  `.build/v1-spec-final-debug-tests.log`.
- The real-provider fixture remains skipped; these totals do not establish actual
  provider nonhydration, revoked native grants or hardware qualification.
- `bash scripts/lint.sh`, `shellcheck scripts/*.sh` and `git diff --check` pass.
- Final optimized at `7c56b0d`: suites passed, reporting 123 coordinator, 13 model,
  2 worker and 18 workspace functions. Hosted discovery matches all 123 coordinator functions;
  production XPC/parser staging and signatures passed. Local log:
  `.build/v1-spec-final-optimized-7c56b0d.log`.
- Standards and Spec reviewers independently verified their concrete findings were
  resolved in `7c56b0d`, with no additional concrete safety, correctness or hard
  standards issue in the reviewed changes. This is not a proof of arbitrary
  natural-language completeness or release qualification.
- `bash scripts/model-smoke.sh` passed against `7c56b0d`, using the existing model
  with networking and original SwiftPM build-product reads denied. The packaged
  diagnostic passed actual PDF/OCR and English/Spanish text naming, byte/token
  preservation and reopened undo; metadata/date/case/separator/prefix and recursive
  tasks; newest-first rename/sort-chain undo; clarification/refusal; a complete
  303-file plan with confirmation preventing mutation; unchanged context rejection;
  cancellation/drain and subsequent inference; failed/cancelled/successful model
  replacement. No additional model download occurred. Local log:
  `.build/v1-spec-model-smoke-7c56b0d.log`. This is a diagnostic-bundle smoke, not
  actual native picker/GUI, clean-user installation or representative qualification.

The initial optimized baseline attempt overlapped addition of the new regression
tests and failed. It is not presented as a verified optimized result. Final
verification uses a separate log against committed source.

Owner changes to `GLOSSARY.md`, `docs/spec.md` and pre-existing untracked files were
not edited or staged; content/index fingerprints match the pre-work record.
No dependencies, app release, installation replacement or source push was added.
The owner-approved installed app and old notarized DMG were not overwritten.

#19 is ready to close as implemented and locally verified. Test function totals
above include the explicitly skipped real-provider test; no executed pass is
claimed for it. The concrete reviewed defects are resolved, not every possible
natural-language interpretation or external-filesystem race.

## Remaining milestone work

This is executable-spec implementation evidence, not a declaration that milestone
#1 or a public release is complete. Qualification and explicit owner dispositions
remain in #15, current-source packaging/distribution in #16, and the previously
deferred accessibility/system-effects review in #18. Earlier owner-deferred formal
undo-cancellation, native-offline and diagnostic-export reruns remain deferred and
are not reinstated by this work. The old notarized DMG does not cover these fixes
or the approved workspace/icon redesign.
