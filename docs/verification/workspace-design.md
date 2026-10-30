# Workspace A implementation — #17

2026-10-30. The owner approved the native Workspace A prototype after confirming
the header-overlap correction, then authorized production implementation. Work is
isolated on `feat/issue-17-workspace`, based on `d6b99e7`. The prototype remains on
`prototype/issue-17`; its lab controls and alternative layouts are not production code.

## What changed

Organize and History now share a native split-view workspace. The file table has
the main content area, with a bounded task composer below it and system toolbar
actions above it. Settings combines local model setup and storage; diagnostics
remain available through Help. Detailed format/scope/privacy guidance lives in an
anchored help popover rather than permanent paragraphs above the files.

One workspace-owned observable model retains operation lifetime, progress, partial
results, pending confirmation and recovery state across sidebar navigation. File
authority stays in the existing coordinator. The no-preview workflow, explicit
recursive intent, separate write grants, >100-file confirmation, 1,000-file limit,
local-only inference and non-overwrite recovery are unchanged. No task-engine,
model, journal schema, deployment target, entitlement, or dependency changes were made.

History titles are derived from recorded folder paths. Existing records have no
task timestamps or request titles, so the UI says dates are unavailable and keeps
journal order. It does not invent dates or begin retaining private requests.

Downloads remain service-owned when Settings closes. Pause/Cancel remain explicit
and retain the existing writer-quiescence and partial-cleanup behavior. Opening
Settings or navigating does not start a download. Model-changing actions are
unavailable while a file task is active; an existing transfer can still be stopped.

## Window and refresh behavior

- Switching Organize/History does not cancel planning, execution or undo.
- Closing the workspace requests cancellation and keeps completed durable changes.
- Global organizing commands are disabled while the workspace is closed; navigation
  commands reopen it, and task commands focus it before acting.
- Reopening an idle workspace refreshes the remembered folder before submission
  re-enables, including files that arrived while the window was closed.
- Same-folder refresh retains the inventory while loading, so the table and composer
  remain mounted. Filtering survives and selection is intersected with current IDs.
  Failed/cancelled inspection clears untrusted inventory instead of presenting it
  as current authority. Selecting another folder resets that folder's browsing context.
- The approved viewport-bound layout replaces the unsuccessful titlebar-padding
  workaround. No private window-view manipulation or guessed header offset is used.

## Automated verification

The app test target uses real temporary folders/coordinators with injected local
planning completions and small model-transfer fixtures. It never accesses the
installed app's files, downloads model weights, or supplies a release authorization
bypass. No production launch-argument test mode was added.

```sh
swift test --disable-automatic-resolution --filter 'WorkspaceModelTests|SettingsLifecycleTests|WorkspaceGeometryTests'
bash scripts/release-tests.sh
bash scripts/lint.sh
shellcheck scripts/release-tests.sh
bash scripts/build-app.sh
```

The release script first stages normally built production parser/service binaries,
then enables testability only in its test-build stage for internal app imports. It
runs the complete signed/contained optimized coordinator suite, model/worker suites,
and the workspace suite. No inspection failures are hidden by skipping cases or
loosening the production parser sandbox.

Observed results before final handoff:

| Check | Result |
| --- | --- |
| Debug workspace suites | 14 tests passed across 3 suites, including a parameterized close/cancel case |
| Optimized coordinator suite | All 117 discovered tests passed in the contained signed host |
| Optimized model suites | 13 tests passed |
| Optimized worker suite | 2 tests passed |
| Optimized workspace suites | Final 14-test run passed; the complete release script also passed its earlier 13-test UI run |
| Swift/plist/shell lint and ShellCheck | Passed |
| Final development app build/signature/icon | Passed; original identifier, sandbox/grant entitlements, macOS 14 target and all icon representations verified |

The final combined release-script run used contained test host
`.build/release-tests/host.DXgz2I/` and passed 117 coordinator, 13 model, 2 worker,
and 13 workspace tests. The subsequent window-reopen freshness regression brought
the workspace suite to 14; both debug and optimized reruns passed at `f00f5f6`.
The final packaged executable has no Testing/XCTest framework linkage.

Workspace cases cover navigation during gated inference, late output after
cancellation/window close, read-grant/readiness enforcement, immutable large-task
confirmation, retained partial changes, undo cancellation, refresh failures, recovery
history despite an unavailable remembered grant, closed-window submission,
same-folder refresh continuity and files arriving while closed. A native hosting test switches the actual sidebar
while inference is gated. A separate native Settings appearance/disappearance test
proves the service-owned transfer survives removal and re-creation of its view.

Geometry checks host the actual production WorkspaceView in an owned AppKit window
at 1080×720 and 900×600, in light and dark appearance, asserting navigation/metadata/
table/composer containment and table/composer separation. They do not establish
every SwiftUI Window-scene startup behavior; the original scene-level bug was
reproduced and corrected in the separately retained, owner-approved prototype.

Ignored local logs include `.build/workspace-ui-tests.log`,
`.build/workspace-ui-release-tests.log`, `.build/workspace-release-tests-final.log`,
and the release script's `.build/release-tests/host.*/` evidence directories.

## Independent review

Review baseline: `git diff d6b99e7...828e501`, followed by
`git diff 828e501...ebe8796` and `git diff ebe8796...f00f5f6`. Reviewers ran
independently; neither edited code. Both follow-up rounds found no new concrete issues.

### Standards

No documented-standard breaches or material actionable Fowler smells were found.
The reviewer found one P2 correctness issue: task commands could become enabled
after the workspace closed. The follow-up added explicit window-lifetime guards,
focus/reopen routing, and a close → blocked submission → reopen regression.
The reviewer confirmed the finding is resolved, with no new concrete issues.

### Spec

One P2 finding: Refresh discarded inventory early, destroying filtering, selection
and the stable composer. The follow-up retains inventory during same-folder refresh
and reconciles selection afterward; a regression checks continuity. The reviewer
confirmed the finding is resolved. Native scroll-position retention is not directly
asserted. No scope creep or further concrete spec mismatches were found.

Review summary: Standards axis — 1 correctness finding resolved, 0 standard breaches;
Spec axis — 1 finding resolved. No unresolved code findings; operator QA remains.

## Morning review and limits

Quit any running Tidy before opening this branch's `.build/Tidy.app`. This is a
local ad-hoc-signed development build, not a new notarized download. It deliberately
keeps `dev.xchrisbailey.Tidy` and therefore shares the installed app's storage and
grants; it is not an isolated install. Use disposable test files, not personal data.

```sh
cd /Users/chris/dev/utils/tidy/.build/workspace-implementation
open .build/Tidy.app
```

Review the file-first layout, toolbar spacing, minimum-size resizing, long paths/
requests/errors, History selection/recovery details, Settings, and Help discovery.
Task invocation stays explicit and changes files immediately; table selection and
filtering do not narrow its scope.

Full-window visual approval, VoiceOver/keyboard-only operation, Reduce Motion,
Reduce Transparency, Increase Contrast and older-OS runtime checks remain pending.
The source uses native controls/materials and keeps the macOS 14 deployment target;
this is not a hardware/OS qualification or a claim that Liquid Glass behavior has
been fully reviewed on every configuration.

Optional fixture renders live in `.build/workspace-review/` when tests are run with
`TIDY_WORKSPACE_SNAPSHOTS`. They use the real view with invented data, but native
cached rendering does not faithfully capture sidebar vibrancy/composited text.
They are not full live-window screenshots or acceptance evidence for those effects.

No installed app or preserved notarized DMG was replaced. No new notarization,
GitHub push, public release, or App Store submission was performed. The issue stays
open for the owner's morning review. Earlier owner-deferred formal checks were
not reintroduced as required manual wizard reruns.
