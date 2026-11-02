# #15 — stable identity feasibility gate

2026-11-01. Phase 1 of the approved
[identity plan](../../brain/plans/01-stable-filesystem-identity/overview.md), based
on `dc5ea7ee`. **Decision: STOP before production activation.** The host supplies
a promising capability candidate, but durable volume-incarnation safety across
clone/restore/rollback is not established. No production identity policy changed;
the [birth-time undo limitation](stable-v1-birthtime-investigation.md) is not fixed.

## Diagnostic interface and capture

`TidyIdentityTestWorker capture <owned-fixture-path>` is a test executable, not a
production backend. It emits bounded JSON containing full-width file ID,
persistent volume UUID bytes, supported/valid format capability masks, birth time
as a control observation, and a deliberately named
`documentedCapabilityCandidate` Boolean. That Boolean is **not** proof that a
volume namespace is safe across restore or that undo is authorized.

Capture uses no-follow, nonblocking, close-on-exec descriptors. Object and volume
attributes come from the same descriptor through `fgetattrlist`; the worker checks
the descriptor against the entry, rechecks type/dataless state, device/inode and
birth time, and compares the full file ID to `fstat`. Packed returned masks and
lengths are checked before decoding. An absent/unknown field is rejected, not
guessed. `ATTR_VOL_INFO` is a request flag, not a returned data field. No source
contents are read, and no file metadata is changed by capture.

Positive opt-in tests require the capability in both valid and supported masks,
not merely stable tuple behavior. The executable and tests remain isolated from
`Sources/`; existing no-follow, freshness, permission and identity checks remain
unchanged. This diagnostic does not implement ancestor pinning, final mutation
binding, single-link eligibility, historical proof or namespace ambiguity handling.
Its observation of equal hardlink IDs does not authorize hardlinked task inputs.

## Observed host results

Host remains M4 Max / 36 GB / macOS 27.0.1. Current SDK declarations make
`fgetattrlist` available since macOS 10.6; compilation targets macOS 14, but no
macOS 14 runtime qualification was performed.

| Check | Outcome |
| --- | --- |
| Ordinary-user descriptor capture | PASS on the owned APFS fixture: nonzero volume UUID, full file ID equals inode, `PATH_FROM_ID` valid and supported. |
| Signed actual App Sandbox capture | PASS for a synthetic file/directory inside the uniquely identified probe's own container. |
| Ungranted outside access | PASS as a denial control: the same sandboxed executable refused `open` on the separately owned worktree fixture. |
| Directory birth-time rewrite | PASS for the candidate tuple: a controlled 74 ns change retained file ID/UUID across fresh processes; changed birth time was observed exactly. |
| File rename | PASS: file ID/UUID retained across fresh processes. |
| Identical-content replacement and APFS file clone | PASS: distinct IDs from the original. File cloning does not test volume cloning. |
| Hardlink control | Expected shared ID observed; production hardlink restrictions are unchanged. |
| Symlink and FIFO | PASS: diagnostic rejects both without opening content or blocking on FIFO. |
| Read-only remount | PASS twice on the previously authorized 256 MiB case-sensitive APFS image: same file ID/UUID; image detached afterward. |
| Whole-volume clone, restore, rollback, duplicate namespace | UNVERIFIED; candidate tuple alone does not attest volume incarnation. |
| Missing/unsupported capabilities on a real filesystem | Not exercised; parser rejects missing fields and the candidate requires both masks, but negative-platform qualification remains. |
| Reboot, minimum macOS, selected external folder/provider under App Sandbox | UNVERIFIED; own-container capture is not external security-scoped grant qualification. |

The host format-supported mask was `26963679`, valid mask `134217727`.
The case-sensitive image reported supported `10186719`, valid `134217727`.
Both included `VOL_CAP_FMT_PATH_FROM_ID` in both masks. A trusted parent-side
Darwin metadata observation independently corroborated the packing and file ID.
No mount other than that previously authorized disposable image was used.

## Isolation and failed harness attempts

Tests launch the known diagnostic with empty/allowlisted environment values,
network/write/fork denial, denied home/session-temp reads except the executable
and synthetic fixture, a 4,096-byte output limit and a 15-second parent timer.
Other system/runtime paths remain readable for dyld. The worker also has a
ten-second alarm. This is **not a general untrusted-code execution sandbox**.

The actual App Sandbox probe uses a unique ad-hoc-signed identity/container with
app sandbox and user-selected-file/bookmark entitlements, without network-client
entitlement. It reads only its own synthetic controls; an ungranted outside-open
control demonstrates effective denial. Direct observations used allowlisted
environment values, CPU/stack/descriptor limits and a parent wall timeout.

Attempts to set hard address-space/data limits failed on this macOS host. No
hard total process-memory bound or complete security-audit execution isolation is
claimed. These are bounded metadata diagnostics, not hostile-input resource tests.

Earlier failed harness attempts remain evidence, not product failures/passes:

- The first red test had no worker executable; subsequent implementation supplied
  the diagnostic interface. The first compile needed explicit unsigned attribute
  flag conversions; no type assertions or production casts were introduced.
- `/var` versus `/private/var` policy aliases initially denied the owned fixture.
  Canonical parent resolution with `realpath` fixed that harness scope.
- Nesting the signed app inside the extra seatbelt profile trapped before main
  during App Sandbox initialization. It is not counted as sandbox capture proof.
  Direct signed-App-Sandbox invocation produced the inside-pass/outside-denial
  observations instead.
- An attempted default-deny runtime-read profile failed in dyld. The final test
  policy explicitly documents permitted system/runtime reads rather than claiming
  complete confinement. Independent review also prompted explicit capability
  assertions, descriptor eligibility rechecks and parent output/time bounds.

## Verification and evidence

Three opt-in integration functions cover rename/replacement/copy, directory birth
rewriting, and link/FIFO rejection through the diagnostic CLI. Final full debug
and hosted optimized suites passed with those tests enabled: **129 coordinator,
16 model, 2 worker and 18 workspace functions reported**; the hosted harness
checked all 129 discovered coordinator functions reported. Both real-provider
tests were skipped in this run, not substituted for the earlier enabled iCloud
evidence. Lint and diff whitespace checks passed.

```sh
swift build --disable-automatic-resolution --product TidyIdentityTestWorker
TIDY_IDENTITY_TEST_WORKER="$PWD/.build/debug/TidyIdentityTestWorker" swift test --disable-automatic-resolution --filter FilesystemIdentityQualificationTests
TIDY_IDENTITY_TEST_WORKER="$PWD/.build/debug/TidyIdentityTestWorker" swift test --disable-automatic-resolution
TIDY_IDENTITY_TEST_WORKER="$PWD/.build/release/TidyIdentityTestWorker" bash scripts/release-tests.sh
bash scripts/lint.sh
git diff --check
```

Without the explicit worker path, these platform qualification tests remain
skipped. They must not become an automatic filesystem-support declaration.

Raw local evidence under `.build/identity-feasibility/` includes
`parent-metadata-observation.json`, `limited-capture.json`, `sandbox-profile.json`,
the failed `app-sandbox-capture.json`, passing `app-sandbox-direct-capture.json`,
`app-sandbox-lifecycle.json`, `app-sandbox-final.json`, `read-only-remount.json`,
focused logs and final full-suite logs. Signed/compiled executable hashes are
recorded in the profile. Only synthetic fixtures in the worktree and unique
container were used. The probe processes exited; container, bundle and evidence
remain retained. No explicit LaunchServices registration, model download, personal-data
task, global permission change, CI or release occurred.

## Gate decision

Independent read-only review found the descriptor packing/capture suitable for
these diagnostics, but recommended **STOP** for a stronger backend. The documented
non-recycling capability is a within-filesystem guarantee; a UUID is not an
authenticated incarnation/rollback token. Stable remounts and distinct file-clone
IDs do not resolve this gap. Do not silently narrow the approved threat contract
or retrofit current IDs into old history.

Before phase 2/activation, establish a safe namespace/incarnation contract and its
failure detection (including clone/restore/rollback ambiguity), or explicitly
revisit the design with the owner. Additional sandbox/platform/negative-capability
evidence also remains. Until then, keep legacy strict refusal and all subsequent
implementation phases paused. #15 and existing owner deferrals remain unchanged.
