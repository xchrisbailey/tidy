# Integration handoff

2026-10-29. Branch: `integration/tidy-v1`. Final application source:
`63f23b103f697beae2f1512d52da0ab27b5b348c`. Later evidence-only commits do not
change the candidate's source provenance. Existing user documentation edits were
preserved and are not part of these implementation commits.

**Public release is blocked. No hardware is formally qualified.** Implementation
and local verification do not close the native, independent-assessment,
hardware/OS, or distribution acceptance gates. Issues remain open deliberately.

## Review and safety

The full implementation was reviewed against original main `736cc24` along
independent standards and spec axes. No hard documented-standard violations were
found. All three maintainability findings and four initial spec defects were
fixed; a subsequent selection-binding regression was also fixed. Read-only
follow-up confirmed the corrected all-files/preservation request, rejected
narrowing, retained PDF-only inspection protection, and fail-closed mixed scopes.

See [review fixes](integration-review-fixes.md),
[selection follow-up](selection-authority-followup.md), and
[recovery safety](qualification-v1-recovery-safety.md). The reproduced descriptor
double-close and inherited lock-lifetime defects were corrected. The original
uninstrumented intermittent failure cannot be uniquely attributed; repeated
focused and full-suite checks are evidence, not proof against every concurrency
failure.

Final-source debug and correctly hosted optimized suites passed in the review
worktree, along with lint. The real-provider test remains skipped without
authorized disposable provider fixtures. The lead independently reran the full
debug suite at `5ab6900` and lint at the final source. Earlier failed unbundled
optimized runs remain recorded; use `bash scripts/release-tests.sh` for the
production XPC service layout. Serial hosted coverage is not concurrency
qualification.

`git diff --check 736cc24...HEAD` reports only whitespace in three verbatim upstream
license/notice locations. Product lint passes; legal texts were not rewritten to
silence upstream whitespace.

## Final optimized candidate

Developer ID, arm64, hardened runtime, secure timestamps; **not notarized or
stapled**. A valid signature does not establish Gatekeeper approval, clean-user
installation, actual native folder grants, or GUI acceptance.

Preserved archive, relative to the primary repository:

```
.build/direct-download/Tidy-Unqualified-63f23b-arm64.zip
SHA-256: b616ac5dc2ed28dd6c9734f80792fd710dc434067b3e932794ddc96b71185c30
```

The lead rebuilt from the clean review worktree using
`bash scripts/package-candidate.sh --unqualified`. Extraction and deep/strict
signature checks passed; BUILD.txt identifies `63f23b1`, Metal and redistribution
notices are present, and links stay inside the bundle. Earlier archives identify
older source and are superseded. No upload or public distribution occurred.

`caffeinate -i bash scripts/candidate-smoke.sh <candidate-output-directory>` passed
against copied final optimized resources and Developer ID nested code, with
network and reads of original build products denied. Actual PDF, OCR, multilingual
text, metadata, recursive sorting, task chains, cancellation and replacement
checks passed with unchanged bytes and reopened undo. This diagnostic is not
native GUI or clean-user evidence.

## Unchanged final corpus

The lead then ran the packaged optimized diagnostic with `--qualify-v1`, under
`caffeinate`, network denial, and original-build-resource read denial, with no
concurrent builds, tests, inference or memory sampler. Same 32 fixtures, rubric,
requests, candidate model and thresholds as the preregistration; no file was
removed or rescored to obtain a pass. Reused approved model storage; no download.

| Measurement | Final optimized observation |
| --- | --- |
| Proposed names | 22 |
| Usable proposals, agent semantic assessment | 21/22 = 95.45% (required >=90%) |
| Useful cryptic names, agent semantic assessment | 21/24 = 87.50% (required >=80%) |
| Other outcomes | Seven abstentions, two unchanged, one skipped, zero errors |
| Complete metadata100, including verified loading | 5.935707376 s; all 100 changed |
| Included verified load | 1.443326709 s |
| Separate content-heavy12, already-loaded model | 7.973495125 s; all 12 changed |
| Native cancellation/drain | 0.007210875 s, one observation, not an upper bound |
| MainActor heartbeat | Maximum gap 0.11015425 s; not native UI evidence |
| MLX allocation peak in this run | 3,202,575,472 bytes; not peak process/unified memory |

All corpus/task byte-preservation and reopened undo checks passed. Agent review
of the actual names retains the same sole unusable OCR result, S03
`Faclura Luna ES809 2026-08-09.pdf`; it is not guessed-corrected or excluded.
Eligible I01/S01 abstentions remain in the cryptic denominator. These are
**agent assessments, not independent human validation**. Small synthetic
corpus success does not establish representative real-world quality.

Host: M4 Max, 36 GB, macOS 27.0.1. Candidate and runtime pins, original failed
qualification, inspection bounds and earlier sampled-memory limitations remain
in [ticket 15](ticket-15.md) and
[corrective results](qualification-v1-corrective-results.md). This machine is a
tested configuration, not a supported-hardware declaration.

## Required next gates

- Actual native setup, consent, folder selection, clarification, confirmation,
  progress/cancel, results, history/task/file undo, storage, diagnostics and
  accessibility; actual quit/relaunch and clean-user installation.
- Real scoped folder grants/restoration/revocation, plus separately authorized
  cloud-only and downloaded provider fixtures proving no hydration.
- Independent naming assessment; minimum hardware/macOS 14 execution, memory
  pressure and parser peak-resource qualification; broader real-world corpus.
- Authorized notarization credentials, signing/notarization/first-launch checks,
  name/legal clearance, hosting and explicit public-distribution approval.

No thresholds were relaxed, cloud inference added, or remote CI used. Follow
[distribution prerequisites](../distribution.md) rather than bypassing the
public-release gate.
