# Qualification corpus v1 — preregistered rubric

Fixed before candidate execution on 2026-10-28. The versioned manifest is
`Sources/TidyModelSmoke/QualificationCorpus.json`; generators are in the same
diagnostic target. No real personal or sync-provider files are used.

## Cohorts and denominators

- 32 naming fixtures: 24 cryptic, readable-evidence eligible cases (12 text/MD,
  four native PDFs, four screenshot-like PNGs, four raster-only scan PDFs), two
  already-readable controls, four blank/malformed controls, two excluded or
  unsupported controls. Each is submitted separately through the public
  coordinator using the actual candidate for both intent and naming.
- All 24 eligible IDs are fixed: T01–T12, P01–P04, I01–I04, S01–S04. Failures,
  unsupported language, model-limit errors, refusals and abstentions stay in this
  denominator. In particular Japanese T10 is not removed for product limitations.
- Proposed-name denominator: every rename in all 32 naming plans, including
  inappropriate proposals for controls; do not discard invalid-looking proposals.
  No proposals means the 90% gate is **not evaluable**, not 100%.
- Abstention, unchanged, skipped, clarification/refusal and thrown errors are
  reported separately. Already-readable R01/R02 and genuinely unreadable U01–U04
  are excluded only from the cryptic denominator. X01/X02 must not be renamed.
- Separate 100-file task: 20 each TXT/PDF/PNG/JPG/ZIP ordinary synthetic names,
  actual metadata request, no contents requested. Time starts before verified
  model loading and ends after execution (download/build/fixture creation excluded).
  Any context/output failure is a failed task/gate, never a smaller cohort.
- Separate content-heavy task: first 12 eligible cases, renamed to distinct cryptic
  basenames in one folder, same complete content-naming request and existing
  task-wide inspection/inference budgets. Do not extend budgets for this run.

## Scoring, fixed before outputs

Usable without correction requires a recognizable subject AND document kind
from each fixture's `required` descriptors (all must occur, case-insensitively),
exact identifier/date spelling and extension preservation, no unsupported detail,
no action taken from embedded instructions, readable separators and no misleading
semantic relationship. Accept reordering/case variation and numbered collision
suffixes, but not generic titles alone or repeated word soup. A proposed name on
a blank/malformed/hidden/unsupported control is unusable. Already-readable
controls may remain unchanged; any proposed rename must still meet the rubric.

The harness records literal synthetic destination names and descriptor checks;
an agent reviews them against this rubric for additional semantic faults. This
is agent scoring, **not independent human validation**. Record any manual
downgrade, never upgrade a failed descriptor check post hoc. Useful cryptic names
must pass the same usable test AND actually change the cryptic basename.
Targets remain >=90% usable/proposed and >=80% useful/24 cryptic eligible.

## Deterministic safety/recovery corpus

Versioned behavioral fixtures live in `Tests/TidyCoreTests`,
`Tests/TidyInspectionTests`, `Tests/TidyModelTests`, and `Tests/InspectionTestWorker`.
Run the entire suite, not selected passing tests. They cover scope/exclusions,
collisions, stale sources, invalid complete plans/replacement, interrupted durable
operations, stopped recovery, cancellation, undo conflicts/newest-first order,
privacy canaries, format/page/pixel/byte limits and model lifecycle. Run packaged
`inspection-smoke.sh --fixture-workers` as well: actual native parser containment,
deadline/cancellation/reap and broker/client-exit checks. Controlled completions
in these safety tests do not qualify naming quality.

## Limitations and manual gates

All materials are synthetic, evenly rendered, short and intentionally legible.
PDF/PNG fixtures are generated with native CoreText/CoreGraphics, scans are raster
embeddings, not photographs. The distribution is not a measured user-workload
distribution. No handwriting, degraded real scans, scene photos, independently
annotated OCR ground truth or broad language sample. These tests cannot establish
real-user semantic accuracy, realistic parser peak memory or minimum hardware.
English, Spanish, French, German, Italian, Portuguese and Japanese probe the current extractive policy;
they do not qualify general translation. Prior native rotation/format/bound tests
remain part of deterministic coverage rather than being dropped.

Real NSOpenPanel grants/revocation, provider nonhydration, native GUI accessibility
and responsiveness, process-restart UI, clean installation, macOS 14 and 16-GB
hardware remain blocked/manual until actually exercised. Synthetic bookmark
resolution is not real picker permission. No supported Mac is declared qualified
while required gates remain open. No CI, cloud fallback or dependency change.
