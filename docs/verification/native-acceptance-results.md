# Native operator acceptance: first completed walkthrough

2026-10-30, 03:24 UTC completion (2026-10-29 local). Tested source `b422b36`,
Developer ID candidate archive SHA-256
`40ee29c35ae67bdd35323efcb6ca8076c31f33b68ff46edf6855505ec8fd5dea`.
Host: Mac16,6 / M4 Max, 36 GB RAM, macOS 27.0.1. This is a tested configuration,
not a formal supported-hardware declaration or notarized clean-user install.

Latest operator observations: **12 PASS, three SKIP**.

- PASS: launch; resumed model setup/readiness; storage visibility; native read
  grant/exclusions; write-grant/clarification/refusal; sorting/results; actual
  quit/relaunch/bookmark restoration; task/file undo; 101-file confirmation;
  partial task cancellation; text-evidence naming; history-clear consent cancel
  and observed keyboard navigation.
- SKIP: live undo cancellation, native offline operation, and diagnostic export.
  Automated coverage does not replace these missing human observations.

Undo was initially recorded FAIL with a PASS note. Its original paths, links and
bytes subsequently matched the baseline, and the operator explicitly confirmed
that both Undo File and Undo Task worked. A new PASS observation records that
confirmation and the independent checkpoint; the earlier failed entry remains in
attempt history. The cause of the earlier checkpoint failure is not established.
Other historical download/checker failures are also retained, not silently erased.

The local `--finish-native` wizard mode targets only the three skipped checks.
For observable undo cancellation it prepares a complete disposable 1,000-file
task, then requests cancellation during its live undo and verifies retained work.
All fixture mutations still require native operator actions. Network changes and
diagnostic saving are likewise manual; skipped/unobservable checks remain SKIP.

Real revocation/provider nonhydration, actual model removal/replacement/history
clearing in an isolated profile, formal accessibility, independent naming review,
minimum OS/hardware/pressure, notarization/clean-user Gatekeeper and name/legal/
hosting approval remain separate open release gates. Public release is blocked;
no issue is closed solely from this partial native walkthrough.

## Owner decision: accept the walkthrough for release preparation

The owner explicitly deferred the three skipped formal checks (undo cancellation,
native offline operation and diagnostic export) and does not require formal
reruns. They will exercise the app hands-on and address discovered defects before
public release. These checks are **non-blocking for continued release preparation**;
do not request another wizard run for them unless the owner asks or reports a bug.

The evidence remains 12 observed PASS and three SKIP with an owner-approved
deferral, not 15 executed passes. The local report records this disposition while
retaining original observations and attempt history. This workflow decision does
not itself approve public distribution or establish the separate untested
hardware, provider, legal or notarization facts.
