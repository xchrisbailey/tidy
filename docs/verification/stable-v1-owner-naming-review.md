# #15 — owner review of fixed-corpus naming

2026-11-03. The owner reviewed all 32 outcomes from the existing actual-model run
retained in `.build/native-matrix/clarification-corpus.log`. No new generation,
corpus change, corrected proposal or denominator substitution occurred.
[Individual responses and source/run hashes](stable-v1-owner-naming-review.json)
are retained separately from the agent's prior scoring.

The 24 eligible cases were presented in small batches with complete synthetic
source text and literal observed proposals or abstentions. The eight controls were
presented as summarized inputs/outcomes. Prior agent scores were not presented in
the batches. The owner had previously seen the known S03 limitation in progress
reports; this is not a fully blinded assessment. PDFs/images were represented by
their generator source text, not visual inspection of rendered files or OCR output.

## Decisions and unchanged scoring

- The owner accepted all 22 proposed filenames and all eight control outcomes.
- I01 and S01 were judged **missed opportunities**: source text supported useful
  invoice names, but the actual run abstained for insufficient evidence. Suggested
  alternatives are not model outputs and are not counted as successful renames.
- S03's observed name is `Faclura Luna ES809 2026-08-09.pdf`, while the source says
  **Factura**. The owner's keep decision is retained, but the preregistered rubric
  prohibits upgrading failed descriptor checks. S03 remains unusable for scoring.

| Fixed-rubric measure | Result |
| --- | --- |
| Usable proposals | **21/22 = 95.45%**, target at least 90% |
| Useful eligible cryptic names | **21/24 = 87.50%**, target at least 80% |
| Missed naming opportunities | I01, S01, retained in eligible denominator |
| Accepted controls | 8/8; two unchanged, five abstentions, one skipped |

Across all 32 cases there were seven abstentions, two unchanged files and one
skipped file. The 22 actual proposals were cross-checked against the retained run;
all 32 review IDs match the versioned corpus. These results add owner human review
to the earlier agent review; they are not a new execution result or a claim that
every observed output was correct.

## Qualification boundary

This completes the **owner's source-text review of the fixed synthetic corpus**.
It is not an uninvolved independent assessment, representative real-world naming
review, broad language validation, visual image/scan inspection or annotated OCR
accuracy evaluation. Those limitations and the other #15 hardware, pressure,
revocation, model-version and identity prerequisites remain. Do not close #15 or
mark aggregate naming quality universally qualified from these percentages.

[Subsequent diagnosis](stable-v1-abstention-diagnosis.md) confirms I01/S01 OCR
misread and fused the identifier/date; a coordinator guard abstained before naming.
The owner's judgments identify useful expected names from source text, not proof
of what OCR supplied. The original review and scores above remain unchanged.
