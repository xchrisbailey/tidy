# #16 follow-up: complete optimized coordinator suite with production XPC

2026-10-29. Implementation source:
`511342671cedac7c45322e85a0543d69eee8820f`, branch `ticket/16-direct-download`,
worktree `/Users/chris/dev/utils/tidy-ticket-16`. Integration at `b5d3703` was
merged/current before and after verification: already up to date.

**PUBLIC RELEASE BLOCKED. Supported hardware: NONE qualified.** This adds local
test launch/packaging, not product behavior or release approval. No production
source, existing test cases/assertions, package dependencies or lockfile changed.
No model-corpus rebenchmark was necessary. No uploads/notarization/publication,
credential discovery, personal sync testing or issue closure occurred.

## Runnable command and boundary

```sh
# From /Users/chris/dev/utils/tidy-ticket-16, with the authorized Developer ID key:
bash scripts/release-tests.sh
# Negative control; must exit 1 with unavailable inspection, not pass:
bash scripts/release-tests.sh --without-service
```

The agreed seam is the existing public `TaskCoordinator` integration tests. The
harness compiles **release**, copies the existing `TidyCoreTests.xctest` and Xcode's
`swiftpm-testing-helper` into a real application bundle, explicitly selects Swift
Testing, and bundles the production inspection XPC service/parser. Inside-out
Developer ID signing uses hardened runtime and secure timestamps for the test
image, app, service and helper, without disabling library validation or injecting
DYLD variables. It checks strict/deep signatures.

Apple test-framework rpaths are linked for loading the test image. Normally linked
production service/parser binaries are staged **before** test-only linker flags and
packaged from that staging directory; they have no test-framework rpaths. No new
parser entry point, production test hook, in-process extraction or DEBUG fallback
was added. The missing-service control proves the release tests require XPC.

The host uses the original CLI test runner's **unsandboxed fixture authority**:
tests create bookmarks programmatically and cannot manufacture native picker grants.
The production app's App Sandbox entitlements are untouched. The independent
broker still installs its restrictive sandbox before accepting IPC; its child
inherits that profile. This is an application-bundle test host, **not** native GUI/
App Sandbox permission acceptance. Xcode's copied testing tool stays local and is
not placed in the direct-download ZIP.

All discovered coordinator functions run without a filter. Source-vs-host
`--list-tests` output must match exactly and be nonempty; the passing run's reported
function count must equal that list. `pipefail` preserves test-process failures.
Then the full optimized model setup/transfer and worker-supervisor suites run in
their normal CLI environment, including their real loopback transfer tests, rather
than adding server permissions to the application host.

Hosted coordinator tests use `--no-parallel`, matching the app's one-task-at-a-time
boundary. Existing concurrency exercised **inside** tests is unchanged. This is
not a claim that arbitrary suite-wide or multiple-app concurrency is qualified.
No inspection deadlines, budgets or worker containment restrictions were relaxed.

## Final complete proper-host result

`bash scripts/release-tests.sh` **PASS, exit 0** at the implementation commit above:

| Scope | Actual result |
| --- | --- |
| Hosted complete optimized coordinator suite | **103 discovered/reported functions, 13 suites, PASS**, 31.563 s; one real-provider test skipped without an authorized fixture. Includes every previously failing PDF/OCR function and all parameter cases. |
| Complete optimized model setup/transfer suites | **11 functions, two suites, PASS**. |
| Complete optimized worker-supervisor suite | **2 functions, PASS**. |
| Total | **115 non-skipped functions**, parameterized cases included; one explicit provider skip. |
| First serial hosted run before final staging/provenance refinements | Same complete 103 + 11 + 2 PASS; retained separately, not substituted for final result. |
| Final missing-service control | **Expected FAIL, exit 1**, same five OCR parameter cases, 15 issues, `inspection unavailable`; no hidden release CLI fallback. |
| Debug regression after final harness run | PASS, same 115 non-skipped functions / provider skip. |
| Packaged native inspection `--fixture-workers` regression | PASS: native PDF/PNG/scan tasks, bytes/reopened undo, controlled worker failures/cancellation, effective read/write/network denials, reap/abrupt-parent cleanup. |
| Strict lint, five plists, all shell syntax, `git diff --check` | PASS. |
| Invalid harness arguments / invalid signing identity | Rejected with exit 2 before builds/signing. |

Final proper-host output directory:

```text
/Users/chris/dev/utils/tidy-ticket-16/.build/release-tests/host.YY5kTq/
```

Contains signed **Tidy Unqualified Release Tests.app**, staged production binaries,
`BUILD.txt`, both discovery lists, `core.log`, `model-supervisor.log` and copied
whole-command log. `evidence/` retains 13 construction/failure/final/regression logs
with a `SHA256SUMS` manifest, copied from the approved temporary log directory.
Negative-control host:
`.build/release-tests/host.ehXh7A/`, with its own failed `negative.log` and provenance.

Host/test/service/helper signatures were individually verified with team
`5U2B7W5F39`, hardened runtime and timestamps. Host CDHash:
`0ea3eb4a1313535116cf5a159744a163ae0a0e87`. Signed optimized test-image SHA-256:
`71dd674cb7360198c8c515cef5ff6999641a029dd205e847d5357581c1a9c9db`.

**The hosted service/parser CDHashes exactly match the retained download candidate**:

| Code | Matching CDHash |
| --- | --- |
| `dev.tidy.inspection.xpc` | `d97365090ef1db512ab4dfdcc83db9419503e167` |
| `TidyInspectionHelper` | `ffad53134a104006a211b97cc8202c12f7c04fbd` |

This is evidence that the host did not substitute a less-contained inspection
implementation; native grant/UI/hardware qualification still does not follow.

## Failed history is retained

The original `swift test -c release` unbundled run remains **FAIL**, seven PDF/OCR
functions / 84 issues. The unbundled CLI runner is unsupported for these production
XPC cases; it is not relabeled as passing. The proper-host command above provides
the missing full optimized seam coverage.

Harness construction exposed additional failures; none were accepted as success:

- `install_name_tool` could not grow existing load commands: abandoned in favor of
  test-image link-time rpaths, with normally linked production helpers staged first.
- Passing a bundle directory instead of its Mach-O image caused loader SIGTRAP.
- Omitting `--testing-library swift-testing` selected an empty legacy entry point:
  zero tests was **not accepted**. Explicit entry-point selection and nonempty exact
  discovery/count checks now reject that class of mistake.
- An App Sandbox host correctly rejected programmatic fixture bookmarks with
  `writeGrantRequired` (five issues). No fake native grant or production entitlement
  exception was added; the test-only host explicitly retains CLI fixture authority.
- The first complete **parallel hosted** run reached XPC but failed four PDF/OCR
  functions / 35 issues, with real inspection deadlines during concurrent fixture
  work. Later OCR cases passed. Full serial runs then passed without budget changes.
  This scheduling comparison is **not a complete diagnosis or fix of contention**;
  arbitrary parallel stress remains unqualified and this failed run remains failed.

Logs are retained under
`/private/var/folders/jc/5pmbdfgj29bgb2ftjl_t4jph0000gn/T/opencode/`:
`ticket16-host-negative.log`, `ticket16-host-negative-rpath.log`,
`ticket16-host-negative-image.log`, `ticket16-host-negative-final.log`,
`ticket16-host-negative-xpc.log`, `ticket16-host-positive.log` (parallel failure),
`ticket16-host-serial.log`, `ticket16-host-final.log`,
`ticket16-host-final-negative.log`, `ticket16-host-debug-regression.log`,
`ticket16-host-containment.log`. Earlier #16 failed-run logs remain as documented.

## Artifact retention and remaining gates

No candidate rebuild was needed: product source is unchanged. The important
existing signed ZIP is retained for the lead to copy, untouched:

```text
/Users/chris/dev/utils/tidy-ticket-16/.build/direct-download/unqualified-5e41cbc6ff4b.9BE5ro/Tidy-Unqualified-Development-arm64.zip
SHA-256: 898224cdbb69f41f71616b471000f8315c26666be5407d055f4c71f68499af65
```

It remains **unqualified, unnotarized, unstapled**, with the previous recorded
Gatekeeper rejection. This follow-up does not alter or republish its bytes.
`scripts/package-release.sh` still refuses before any release actions.

The original recovery `.busy` investigation belongs to concurrent #15 work; no
core fix is attempted or claimed here. Independent model/hardware qualification,
representative files, native picker/grants/revocation, clean-user GUI setup/tasks/
history/relaunch/offline/accessibility, real-provider nonhydration, actual process/
power-loss recovery, naming/legal review, authorized user-managed notary credentials
and final distribution/hosting approvals all remain open. No issue is closed.
