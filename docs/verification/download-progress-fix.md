# Model setup appears stuck near 2 MB

2026-10-29, release preparation. The operator reported `model.safetensors` still
downloading with the display near 2 MB after 2–10 minutes. Native walkthrough
setup/storage checks correctly remain failed until the updated app is retested.

## Reproduction and cause

Confirmed public-seam regression command:

```sh
swift test --disable-automatic-resolution --filter setupReportsReceivedBytesBeforeTheCurrentFileCompletes
```

Before the fix, two consecutive runs failed in about 1.13 seconds: the controlled
HTTP server had sent 100,000 bytes while the observable setup reported zero
received bytes. The same real URLSession transfer subsequently completed,
verified its SHA-256, and reached the controlled runtime successfully. This
isolates the progress-reporting defect from download integrity or completion.

Production setup counted only whole verified files. The pinned files before the
weights total 1,677,776 bytes; the next file is 2,263,022,417 bytes. No URLSession
partial-write events reached setup, so the number stayed near 1.7 MB throughout
that entire file. The original label even described it as verified-file progress.

## Fix

URLSession's partial-write/resume callbacks now flow through a bounded newest-only
stream to the observable setup. Its total combines completed verified files with
bytes received for the current file. The UI says **received**, not verified.
Callbacks drain before transfer returns, preventing late progress from replacing
verification, cancellation, or next-file state. Existing transfer conformers keep
their completion-only default; production URLSession supplies live progress.

Size/hash verification, complete-install promotion and native inference readiness
remain unchanged. Received bytes do not make a model ready. Cancellation still
waits for writer quiescence before any explicit partial cleanup. No user partial,
resume data, model, history, grant or selected file was inspected or removed.

## Evidence and limits

- Regression goes green in about 1.12 seconds; all 13 model lifecycle/transfer
  functions pass, including genuine resume/ignored-range, corruption, cancellation,
  and working-model replacement cases.
- A bounded real-provider 1-MiB request returned HTTP 206 in 0.63 seconds. No signed
  redirect URL or credential was printed.
- A separately signed App Sandbox probe compiled the same production setup,
  transport and manifest sources, with the production entitlements. It downloaded
  the ordinary initial files, observed **1,457,663 live weights bytes** beyond that
  prefix in **1.81 seconds**, then paused, awaited quiescence and explicitly cleaned
  only its fresh probe namespace. It did not load a model or access the user's
  production app container. This verifies the real sandboxed transfer/progress
  path, not complete download or native UI qualification.
- macOS denied the agent access to the production app container. That denial was
  respected; no Full Disk Access, identity bypass or container-data extraction was
  attempted. The health of the operator's existing in-flight transfer is therefore
  not inferred from the progress fix or probe. It needs a native retry.
- Lint passes. No dependencies, telemetry, provider changes, threshold relaxations
  or remote CI were introduced.
- The complete debug suite passes: 117 reported coordinator functions, 13 model
  functions and two supervisor functions, including parameterized cases. The
  existing real-provider fixture remains explicitly skipped. This is not a native
  setup pass or a complete real-model download.

The replacement native artifact must retain the app identifier, authorized
Developer ID identity and model-storage paths. Pause the old transfer and quit
normally before opening the replacement; use Download / Resume, not Cancel and
Remove Partials. Keep the original failed observations and record the retry as a
new attempt with its new source/artifact hash. Public release remains blocked.

## Replacement handoff

Application source: `b422b36fa0db7d6eee0e030200d2de7285aa5e36` on `release/v1`.
Developer ID hardened candidate built in a clean detached worktree and extracted
with deep/strict signature verification. Bundle identifier and model-storage
paths are unchanged. Preserved archive:

```
.build/direct-download/Tidy-Unqualified-b422b36-arm64.zip
SHA-256: 40ee29c35ae67bdd35323efcb6ca8076c31f33b68ff46edf6855505ec8fd5dea
```

The regression also passed ten consecutive repetitions. The complete properly
hosted optimized suite passed via `bash scripts/release-tests.sh`: 117 reported
coordinator functions, 13 model functions and two supervisor functions, with the
same provider skip. No new empirical naming/hardware qualification is claimed.

The local native wizard now has `--retry-download` (replacement launch, resume,
storage, summary) and `--continue-native` (remaining checks). It records the retry
artifact source/hash and retains superseded observations in attempt history.
The original failed setup/storage observations were not rewritten. The immutable
wizard library, shell/Python syntax, and isolated report-history controls were
checked; no native retry was performed by the agent. This replacement is not
notarized, and public release remains blocked until actual native results and
the other existing gates pass.

## Operator retry result

The local retry completed on 2026-10-30 at 02:57 UTC (2026-10-29 local).
The operator confirmed success in chat, and the retained native report records
PASS for replacement launch, resumed model setup/readiness and storage visibility
against `b422b36` and archive hash `40ee29c35ae67bdd35323efcb6ca8076c31f33b68ff46edf6855505ec8fd5dea`.
The original `63f23b1` failures remain in attempt history. This clears the reported
download/progress blocker for the tested setup, not every native acceptance gate
or a fresh clean-user installation.

The remaining folder-grant, task, cancellation, relaunch/undo, offline and private
export checks have not yet been recorded in this run. Continue the existing local
wizard with `--continue-native`; do not mark those checks passed from the three
successful retry observations. Hardware qualification and public release remain
blocked by their separate evidence requirements.
