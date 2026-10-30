# Experimental beta 1: local artifact verification

Prepared on the owner-selected experimental-beta track, not as qualified v1.
Source `6bcb430a8680` includes the reviewed executable-spec fixes, approved
workspace/icon, MIT license, build 2 and signed beta provenance. No app installation,
Apple submission or public download was performed by these checks.

## Results

- Fresh Developer ID/hardened-runtime arm64 beta built from clean committed source.
  Nested signatures, all icon sizes, bundled Metal resources and MIT/third-party
  notices passed. Model weights are not bundled.
- Beta and legacy-unqualified mounted DMG tests passed: read-only UDZO image,
  Applications link, warnings, exact app file/link comparison and unchanged ZIP.
  Unsafe/case-alias/symlink and cross-mode protections remain enabled.
- Provenance review found a reproduced relabeling defect: a renamed older signed
  app plus forged unsigned beta wrapper was accepted before the fix. The same
  input now fails. Beta names, source/flavor/tag and MIT license are required inside
  the verified signature seal. Reviewer follow-up confirmed resolution.
- Complete packaged offline real-model smoke and native parser containment passed.
  Network and original build-resource reads were denied for the model diagnostic.
  Existing weights were reused; no download or cloud inference occurred.
- Full debug and correctly hosted optimized suites passed: 123 coordinator,
  13 model, 2 worker and 18 workspace functions reported. The real-provider
  fixture is explicitly skipped, not an executed pass. Hosted discovery matches.
- Lint, ShellCheck and diff checks passed. No app-test CI added.

## Unchanged 32-fixture corpus

M4 Max, 36 GB RAM, macOS 27.0.1 (26A434); no simultaneous builds/tests during
the diagnostic. Same versioned corpus, thresholds, model and denominators as the
preregistered rubric. The agent reviewed the actual proposals against the fixture
contents; this is **not independent human assessment**.

| Observation | Result |
| --- | --- |
| Usable proposals | 21/22 = 95.45% |
| Useful eligible cryptic names | 21/24 = 87.50% |
| Other outcomes | Seven abstentions, two unchanged, one skipped, zero errors |
| Metadata 100, including verified model loading | 5.976347875 s; 100 changes |
| Verified model loading included above | 1.463043417 s |
| Separate content-heavy 12, already-loaded model | 8.035970042 s; 12 changes |
| Native cancellation/drain, one observation | 0.008707708 s |
| MLX allocation peak | 3,202,575,472 bytes; not peak unified/process memory |

Byte-preservation and reopened undo passed. OCR case S03 remains unusable:
`Faclura Luna ES809 2026-08-09.pdf`, not corrected or excluded. I01/S01 abstentions
remain in the eligible denominator. Synthetic timing/scores do not qualify other
hardware, macOS versions, representative real-world naming or memory pressure.

## Exact local artifacts — not notarized or publication-approved

- ZIP: `Tidy-0.1.0-beta.1-arm64.zip`, 12,759,764 bytes.
  SHA-256: `4f80f4106fd8a327b19992fd4e78a312be4f86f15d209ebc189fd653fbfdbd04`.
- DMG: `Tidy-0.1.0-beta.1-arm64.dmg`, 15,005,273 bytes.
  SHA-256: `54a1cee04bfb277b2c91facf5c3aa60ae70c37c49fd691a1b4789c808b04e989`.

Retained under this worktree's `.build/direct-download/`:
`experimental-beta-6bcb430a8680.pVsWhB/` and
`dmg-experimental-beta-6bcb430a8680.Ei8IxR/`. Machine-readable paths, logs and
results are in `.build/beta-verification/`; the initial superseded candidate and
provenance regression logs are retained separately.

The owner deferred #18 until after release and explicitly selected beta caveats
instead of claiming full qualification. They subsequently approved merging PR #20,
this exact image's Apple submission and public prerelease of its stapled derivative
only after Accepted notarization and artifact checks. They chose to retain Tidy
with naming clearance unresolved and defer the clean-user GUI install for this
beta. These are dispositions, not verification passes. The stapled image will have
a separate final hash; merging alone does not authorize an unnotarized download.

## Approved Apple submission and final artifact

Apple accepted submission `f1536e2f-958b-453f-87c7-c706dbd504cd`; the downloaded
notary log reports zero issues. The original submitted image remains unchanged.
A separate copy was stapled, validated and checked for image integrity and strict
signatures. Both DMG-open and mounted-app-execute Gatekeeper assessments report
`Notarized Developer ID`. Every signed app file/link matches the approved candidate.
No app was installed or launched by these checks.

Final public-artifact candidate: `Tidy-0.1.0-beta.1-arm64.dmg`, 15,007,173 bytes.
SHA-256: `84fd9283890a23423b1ff3cccae7a7fe185696138c6cc71b45c9f46328f61797`.
Retained in `.build/beta-publication/` with `SHA256SUMS`, Apple log, Gatekeeper
outputs and machine-readable receipt. Publication remains conditional on the
recorded approval and exact-artifact upload verification; the unnotarized ZIP
is not a public release asset.

## Publication verified

PR #20 merged at `55404f3`. GitHub prerelease `v0.1.0-beta.1` targets the exact
tested app source `6bcb430a8680d22d36ec63a64e281f3368dea80b`; only the final
notarized DMG and `SHA256SUMS` were uploaded. Both draft-asset digests and anonymous
public downloads match the recorded final SHA-256. No credentials are required to
download them. The diagnostic ZIP was not published.

Release: https://github.com/xchrisbailey/tidy/releases/tag/v0.1.0-beta.1.
Landing page: https://tidy.srcery.computer/; owner-managed CNAME preserved, HTTPS
verified/enforced. Pages deployment from `9485a72` succeeded. Browser verification
confirmed the beta CTA reaches the public release; automated page accessibility
reported zero violations. This does not perform the separate native-app review #18.
