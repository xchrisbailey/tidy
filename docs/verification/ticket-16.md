# #16 — local direct-download candidate, not a release

2026-10-29. Worktree `/Users/chris/dev/utils/tidy-ticket-16`, branch
`ticket/16-direct-download`, clean requested integration base `b5d3703` confirmed.
`git merge --no-edit integration/tidy-v1` reported already up to date.

**PUBLIC RELEASE BLOCKED. Supported hardware: NONE qualified. Keep #16, #15 and
parent #1 open.** This is provisional downstream implementation, not acceptance.
No publishing/push/upload, notary submission, account/credential setup, new
dependency, CI, cloud service or personal sync testing occurred. The primary
worktree's dirty documents were not edited.

## Proper-host optimized-suite follow-up

The original seven-function unbundled release failure below remains failed history,
not a pass. A subsequent [full optimized application test host](ticket-16-hosted-tests.md)
runs the **same unchanged 103 coordinator test functions**, with the production
XPC service/parser in a signed `.app`, plus complete optimized model/supervisor
suites: **115 non-skipped functions pass**, one provider skip. The host verifies
complete matching discovery; missing-service controls fail. Production source,
test assertions, parser isolation/deadlines and app entitlements are unchanged.
The hosted suite is serial; a parallel deadline-failing attempt is retained and
does not become concurrency qualification. All manual/release gates remain open.

## Artifact and signing

Candidate source commit: `5e41cbc6ff4b` (implementation begins at `30b412e`).
Built with optimized `release` configuration, arm64, pinned lockfile, Xcode 27.1 /
Swift 6.4 on the existing M4 Max / 36-GB / macOS 27.0.1 machine. No hardware claim
follows. Packaging is repeatable with recorded inputs, **not bit reproducible**:
Developer ID timestamps and ZIP metadata vary.

Artifact directory (local, ignored, not uploaded):

```text
/Users/chris/dev/utils/tidy-ticket-16/.build/direct-download/unqualified-5e41cbc6ff4b.9BE5ro/
```

| Artifact relative to that directory | SHA-256 |
| --- | --- |
| `Tidy-Unqualified-Development-arm64.zip` | `898224cdbb69f41f71616b471000f8315c26666be5407d055f4c71f68499af65` |
| `Tidy-Unqualified-Development/Tidy Unqualified Development.app/Contents/MacOS/Tidy` | `ceeeb67b3f689b27d24b85390da9acc36cdb7a4e10e5935e92ae5ee2174d7ded` |

`BUILD.txt` in the payload records source/toolchain/lockfile. Sibling
`signature.txt`, `entitlements.plist`, `bundle-sha256.txt`, `SHA256SUMS` retain
signature/entitlement and individual bundle-file evidence. `extracted/` retains
the native `ditto` ZIP round trip and separate **Tidy Unqualified Diagnostic.app**;
that diagnostic is not in the download ZIP. No model weights are bundled.
Installation/privacy/recovery guidance and prior corrective evidence are bundled.

All app, XPC service and parser helper signatures have hardened runtime and secure
timestamps, using the authorized Developer ID Application identity
CHRISTOPHER BRIAN BAILEY (`5U2B7W5F39`), certificate SHA-1
`DDB64DD6A0BB35AA612980AEDD27B781C6A1E6F0`. Private-key access succeeded without an
approval blocker; no secret was read. App CDHash:
`929440e484f04c6e71a02685f913149ee91ffa7b`. Strict/deep verification passed before
and after extraction; helper/service identities, runtime/timestamps and exact
`Packaging/Tidy.entitlements` parity were checked. Retained grants remain scoped
user-selected read/write + bookmarks, with network-client for model setup. Native
inspection containment was not replaced with a production CLI/in-process fallback.
Metal resources and third-party notices are present.

**Notarization: NOT submitted / NOT notarized / NOT stapled.** No authorized notary
profile was supplied; no keychain credential search was performed. On the extracted
app, `spctl --assess --type execute --verbose=4` exited **3**, `rejected`,
`source=Unnotarized Developer ID`. `xcrun stapler validate` exited **65**, “does not
have a ticket stapled to it.” These are unresolved distribution failures, not
passes. No quarantine removal, Gatekeeper bypass or real GUI first launch occurred.
[Distribution instructions](../distribution.md) give explicit user-owned authorized
notary submission/stapling steps; the implementation uploads nothing.

An earlier local candidate is retained, superseded because its bundled guide links
did not preserve the distribution/verification layout:
`.build/direct-download/unqualified-30b412ee0885.g7wLHQ/Tidy-Unqualified-Development-arm64.zip`,
SHA-256 `0a0eadaeb9e3a08189c09e8d7a933e22d170449fec1ffa598b78f56a5b0f77dd`.
It is also unqualified/unnotarized and must not be relabeled or published.

## Actual local checks

| Check | Result |
| --- | --- |
| `swift test --disable-automatic-resolution` | PASS twice, including final integrated-tip repeat: 11 model + 2 supervisor + 103 reported core functions, including one provider skip = **115 non-skipped functions**. Parameterized cases included. |
| `swift test --configuration release --disable-automatic-resolution` | FAIL: model 11 and supervisor 2 pass; core 103 reported functions, one provider skip, **84 issues in seven PDF/OCR test functions**. Retained, not converted to a pass. |
| Focused release `--skip-build --filter screenshotEvidenceNamesAndReopenedUndoPreservesBytes` | FAIL: all five parameter cases, 15 issues, inspection unavailable; reproduces the unbundled release inspection limitation. |
| `bash scripts/lint.sh` | PASS strict Swift format, five plists, syntax for all shell scripts. |
| `git diff --check` | PASS. |
| Candidate CLI rejection checks | PASS: absent/incorrect mode and dirty source exit 2; diagnostic missing path exits 2. Public release exits 1 normally, with `--approved`, and with approval-looking environment variables; no artifacts/sign/upload. No automated new test seam assumed approved. |
| `bash scripts/package-candidate.sh --unqualified` | PASS twice; clean source, optimized arm64 native bundle, inside-out Developer ID signatures, ZIP/checksums. Latest source/output identified above. |
| Native ZIP extraction and structural checks | PASS: strict signatures, explicit unqualified name, arm64/min-OS metadata, exact app entitlement parity, service/helper authority/runtime/timestamps, compiled Metal, notices, corrective evidence, no `.safetensors`. |
| `bash scripts/candidate-smoke.sh <exact extracted output directory>` | PASS, exit 0: optimized Developer ID diagnostic using extracted candidate resources/signed helpers; original build-resource reads and network denied. Local loading, text/PDF/OCR/Spanish naming, byte preservation, metadata/recursive/task chains, clarification, 303-file confirmation, context rejection, replacement, cancellation and reopened coordinator undo. No GUI acceptance inferred. |
| `bash scripts/inspection-smoke.sh --fixture-workers` | PASS, exit 0: packaged debug App Sandbox native PDF/PNG/scan naming, bytes/reopened undo, seven controlled worker cases, read/write/network containment, cleanup/reap and abrupt-client-exit cleanup. Not the final GUI bundle. |
| Gatekeeper / staple validation | FAIL as expected for unnotarized candidate; exit 3 / 65. Not acceptance. |
| Clean-user native install/setup/tasks/history/offline | NOT RUN; native GUI/clean-user environment unavailable here. |

The release CLI failure is explained by `Sources/TidyCore/NativeInspection.swift`:
the SwiftPM test-runner supervisor adapter is intentionally inside `#if DEBUG`;
optimized production inspection requires the bundled XPC service absent from the
CLI runner. No production code/test assertion was weakened. An optimized packaged
diagnostic is distinct evidence, not a green release CLI suite or real GUI test.

Command logs retained outside git under
`/private/var/folders/jc/5pmbdfgj29bgb2ftjl_t4jph0000gn/T/opencode/`:
`ticket16-release-tests.log`, `ticket16-release-focused.log`,
`ticket16-debug-tests.log`, `ticket16-package.log`, `ticket16-final-package.log`,
`ticket16-candidate-smoke.log`, `ticket16-inspection-smoke.log`,
`ticket16-final-debug-tests.log`. Copies also sit beside the final candidate ZIP.

## Carried evidence and open gates

The unchanged [#15 corrective results](qualification-v1-corrective-results.md)
report **21/22 usable proposals (95.45%)**, **21/24 useful cryptic files (87.50%)**,
and complete 100-file execution **6.46154 s including load**. This was synthetic,
agent-scored evidence, not independent review or hardware qualification. One
confident OCR-derived unusable name and eligible abstentions remain. Those scores
were carried forward, not independently rescored by #16.

The prior intermittent recovery `.busy` remains **unlocalized/not fixed** even
though later suites pass. No full safety qualification is claimed. Independent
human scoring, representative files/scripts/handwriting, minimum hardware/OS,
memory pressure/parser peaks, real power loss/app-process recovery, native grants/
revocation, real-provider nonhydration and GUI/accessibility acceptance remain open.

[Installation guide](../install.md) explains free/account-free intent, the ~2.28-GB
model and ~7.37-GB setup reserve, consent/resume/removal, offline limits, app-managed
model/history paths and controls, retained-path privacy, sync-service transmissions
and best-effort undo. The renamed candidate shares the development sandbox identity;
it is not a separate storage namespace or a clean-user install.

Primary-source research found related Mac software **Tidy Up**. Name availability,
legal clearance, project distribution terms and model/dependency notice/provenance
review remain owner gates; free product intent is not a redistribution license.
Authorized notary profile/account standing, final-artifact human review and clean
Gatekeeper checks, approved HTTPS hosting/support/privacy location and publication
access are unresolved. No accounts, payments, domains or credentials were acquired.
See the [complete unresolved release checklist](../distribution.md).

`scripts/package-release.sh` refuses unconditionally before building or signing.
There is no flag/environment approval bypass. A future reviewed implementation
must consume actual qualification evidence and explicit owner approvals; neither
an environment flag nor checked boxes can manufacture acceptance.
