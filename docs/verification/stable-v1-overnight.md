# #15 — unattended local follow-up

**Later native resumption:** [Resumed matrix](stable-v1-native-resume.md) records
the checks performed after the owner made the Mac available. The lock-blocked
attempt below remains historical; clarification questions were still not observed.

2026-11-02. Owner authorized continuing locally while unavailable. Work remains on
`ticket/15-permission-revocation`, based on `dc5ea7ee`, with uncommitted diagnostic,
test, design and verification work preserved. **#15 remains open. No hardware is
formally qualified; nothing was merged or released.**

## Production defect found and bounded fix

New coordinator-level format checks exposed a real failure: a JPEG cut to
two-thirds of its freshly encoded bytes still produced OCR and reached naming
with `coverage: wholeImage`. The test failed because content evidence reached the
completion where malformed input should have abstained. A truncated PNG abstained
as insufficient rather than unreadable. Original bytes were preserved.

ImageIO's ordinary and incremental source/global/per-index status probes all
reported complete, including after decode, for these synthetic truncated inputs.
Those status probes were removed after diagnosis; their failed attempts/logs are
retained rather than counted as successful corruption detection.

The parser now performs bounded PNG/JPEG **framing** checks before ImageIO/OCR:

- PNG: signature, initial IHDR, declared chunk extents, image-data presence and
  terminal empty IEND. A truncated declared chunk or missing IEND is unreadable.
- JPEG: segment lengths, scan boundaries, byte stuffing/restart markers and EOI.
  Embedded EOI bytes inside length-delimited metadata do not terminate the image.
- Valid trailing data after the first encoded image terminator remains accepted,
  preserving padded-image compatibility. Other formats retain native handling.

This is not a new decoder or exhaustive CRC/zlib/JPEG-entropy validator. A shortened
entropy stream followed by a fabricated EOI, or framed but corrupt PNG compressed
data, is not ruled out by framing alone; subsequent native decoding still applies.
Do not claim universal malformed-image rejection or full decoded-content proof.
Existing 20 MiB input, dimension/pixel, evidence, worker-supervision and task limits
remain unchanged. The framing walks are linear in bounded input and use constant
auxiliary storage; no new dependency or process-memory guarantee was introduced.

Read-only review found no must-fix bounds/marker issue, while explicitly preserving
those limitations. Specification references:
[PNG chunk structure/IEND](https://www.w3.org/TR/png-3/) and
[JPEG T.81 Annex B](https://www.w3.org/Graphics/JPEG/itu-t81.pdf).

## Expanded actual codec coverage

The existing public-coordinator integration tests now pass **24 negative** and
**10 positive** cases. New coverage includes actual two-frame APNG, HEIF sequence,
truncated PNG/JPEG, missing PNG IEND, invalid declared lengths, JPEG missing only
EOI, terminal lone FF, stuffed/end-like bytes, restart-without-end and an embedded
EOI in metadata followed by a truncated body. Negative cases abstain before content
naming and preserve source bytes.

Positive cases retain actual native OCR, byte-preserving rename, reopened undo and
the existing persisted-private-canary check. Variants include HEIF extension
alias, padded PNG/JPEG, a JPEG with EOI bytes in its comment, and progressive JPEG.
The progressive fixture asserts the actual encoded JFIF progressive property,
not merely a requested encoder option. These are synthetic decoder/coordinator
checks with controlled naming responses—not independent naming-quality assessment.

## Real iCloud content-planning follow-up

Reused only the four previously authorized synthetic files from the
[iCloud qualification](stable-v1-icloud.md). Initial metadata still showed two
cloud-only files dataless/NotDownloaded and two local controls current.

The provider worker now additionally plans content naming including subfolders:
only local-control evidence is accepted by the injected completion, and the plan
must include exactly the two downloaded originals while both placeholders remain
cloudOnly skips. One selection process and two fresh restoration processes repeat
metadata/content planning; the parent checks flags and local bytes after each.
No provider moves/renames or user-data task was executed.

The first injected response failed naming validation. The harness was corrected
to use the documented heading-selection/app-assembled-name response; production
validation was not weakened. Final focused and full debug/optimized runs passed.
Independent final metadata still showed both placeholders dataless/NotDownloaded,
not downloading, and local controls current with original hashes. Placeholder
contents were never opened/read/hashed by the qualification harness after eviction.

This remains coordinator/controlled-completion evidence, not an actual sandboxed
GUI provider task or continuous network attribution. The prior four synthetic
fixtures remain retained at the authorized iCloud path for repeatability.

## Full local verification and unchanged corpus

All passed:

```sh
swift test --disable-automatic-resolution --filter 'unreadableOrExcessiveInputsAbstainWithoutNaming|screenshotEvidenceNamesAndReopenedUndoPreservesBytes'
swift test --disable-automatic-resolution
bash scripts/release-tests.sh
bash scripts/lint.sh
git diff --check
env NSUnbufferedIO=YES bash scripts/inspection-smoke.sh --fixture-workers
env NSUnbufferedIO=YES bash scripts/model-smoke.sh
caffeinate -i env NSUnbufferedIO=YES bash scripts/model-smoke.sh --qualify-v1
bash scripts/build-app.sh
```

The final complete suite commands used the existing provider fixture environment
variables from `stable-v1-icloud.md` and `TIDY_IDENTITY_TEST_WORKER` pointing to the
debug/release diagnostic respectively. **129 coordinator, 16 model, 2 worker and
18 workspace functions reported; both real-provider tests and the three identity
qualification tests were enabled, not skipped.** Hosted optimized coverage checked
all 129 discovered coordinator functions reported. Earlier no-provider runs remain
in separate logs and are not substituted for these final enabled runs.

Packaged parser checks passed normal PDF/PNG/scan tasks, hang/oversize/crash/
malformed/bad-text abstention, cancellation/reaping, denied file read/persistent
write/network and abrupt-parent-exit cleanup. The packaged real-model smoke passed
with network denied and the approved local weights; no download was requested.

The unchanged 32-case corpus was rerun once after the parser fix, without changing
requests, denominators, thresholds, model or rubric:

- Script upper bounds: **21/22 descriptor-usable**, **21/24 cryptic useful**;
  7 abstentions, 2 unchanged, 1 skipped, zero task errors. The known S03 OCR spelling
  error (`Faclura`) remains unusable. These reproduce prior agent-scored results,
  not independent human scoring or a new representative-corpus qualification.
- 100-file task: **100 changed**, **6.502 s including 1.895 s verified loading**;
  all original bytes and reopened undo passed on this M4 Max host.
- Separate content-heavy 12-file task: **12 changed**, **9.459 s**, excluding the
  already completed load; all bytes/reopened undo passed.
- MLX reported peak **3,176,410,216 bytes** for this run. This is not total process
  peak, unified-memory pressure, a hard bound or minimum-hardware qualification.
  The measured main-actor heartbeat gap is not native UI responsiveness evidence.

`caffeinate` supplied only a child-lifetime idle-sleep assertion; it did not unlock
the screen or change a persistent sleep setting. This diagnostic offline evidence
does not complete the owner's deferred formal native-offline walkthrough.

## Native matrix remained blocked by session lock

A fresh isolated development app identity and disposable 101-file confirmation,
clarification/refusal and content-canary fixtures were prepared under
`.build/native-matrix/Fixtures`. On launch, its window was not exposed through
Accessibility. A session-state-only check reported **screen locked / not on
console**. No keys, clicks, coordinate fallback, unlock or login attempt followed.

The isolated app was closed with confirmed process exit and its temporary
LaunchServices registration removed. No model clone was installed. All prepared
paths and hashes remained unchanged. Its bundle was subsequently refreshed from
the current worktree with the framing fix and deep strict signature verification,
but was not relaunched. A second unregister attempt reported not-found (`-10814`);
no new explicit registration was made. Bundle/container/fixtures remain retained.

Therefore native 101-file confirmation/cancel, clarification/resubmission, refusal
and content-retention observations remain **BLOCKED**, not failed product checks
or headless substitutes. Resume them only in an unlocked authorized session, using
the exact owned fixture paths and a cloned—not downloaded—approved model.

## Identity research and other remaining gates

[Primary-source research](stable-v1-volume-incarnation-research.md) did not find a
qualifying ordinary-user public contract that closes clone/restore/rollback
ambiguity. It distinguishes documentation limits from measurements and recommends
keeping phase 2/activation paused. No identity tolerance, marker fallback, private
API, snapshot operation, volume clone/restore or new permission was introduced.

The current best-effort undo limitation remains; existing stranded history was not
repaired. Other gaps still require external evidence or owner input: real TCC
revocation, independent naming review, minimum Mac/macOS and sustained pressure,
a second reviewed production model, the remaining native matrix, #18 accessibility
and #16 distribution dispositions. Formal undo-cancellation, native-offline and
diagnostic-export deferrals remain unchanged.

## Retained evidence and integrity

Raw evidence under `.build/native-matrix/` includes preparation/profile/baseline/
results JSON; failed codec/status-probe logs; passing `codec-focused-final.log`;
initial provider injected-response failures and `provider-content-final.log`;
`debug-all-optins.log`, `optimized-all-optins.log`, `inspection-smoke.log`,
`model-smoke.log`, `qualification-v1.log`; before/after provider state and the current
app build log. Earlier phase evidence stays in its own directories.

All 11 approved-source model hashes were rechecked unchanged. The disposable APFS
image remains detached. Only synthetic fixture data, isolated test identities and
local builds/evidence were used. No personal-file task, global permission/network
change, CI, commit/push/PR publication, merge or release was performed in this
unattended follow-up. Changes remain local for review.
