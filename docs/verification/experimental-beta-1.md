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
instead of claiming full qualification. Working-name risk, permission for this
image's Apple submission/public prerelease, and final-install disposition still
need decisions. Any stapled image gets a separate final hash; do not upload the
unsigned-approval/nonnotarized candidate simply because the PR merges.
