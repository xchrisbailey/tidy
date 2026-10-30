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
swift test --disable-automatic-resolution --filter TidyAppTests
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

Initial implementation results (before the follow-up usability pass below):

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

The owner approved the production visual direction after opening the development
build. Complete state-by-state visual review, VoiceOver/keyboard-only operation, Reduce Motion,
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

## Follow-up usability pass

After the owner approved the production layout, they authorized a focused usability
pass before merging. That pass found a reproducible issue: a long failure message
with no batch result had no scroll surface in the fixed-height Details sheet. The
native regression failed before the correction. Summary text, refresh warnings and
per-file outcomes now share one native scrolling List, with Done kept outside it.
Refresh-only failures also expose Details and pass their complete warning text to
the sheet, rather than relying on a two-line label/tooltip.

Additional accessibility semantics identify the sidebar's readiness control as
Local Model Settings with a readiness value, distinguish Cancel Undo from Cancel
Task, announce concrete progress counts, and hide the decorative welcome icon.
These are implementation improvements, not a claim of a completed VoiceOver audit.

Current automated usability coverage:

- Long error and refresh-warning-only Details sheets have a native scrollable
  document and a Done button inside the window.
- A real native text editor accepts first-responder focus and editing updates the
  request binding without starting a task.
- The actual workspace fits at default/minimum sizes with long directory paths,
  long filenames and a multiline request. The full filename remains in inventory.
- Geometry passes in Aqua, Dark Aqua, Accessibility High Contrast Aqua and
  Accessibility High Contrast Dark Aqua: four native appearances at two sizes.
- The module-wide `TidyAppTests` filter includes all four workspace suites, including
  the new usability regressions. Debug and optimized runs pass all 16 test functions
  (with additional parameterized cases). The complete optimized release-script pass
  also reports 117 coordinator, 13 model and 2 worker tests passing. Local evidence:
  `.build/workspace-usability-pass.log` and `.build/workspace-usability-release-tests.log`.

No user system settings were changed. SwiftUI's Reduce Motion/Reduce Transparency
environment values are read-only here, so tests do not fake overrides or treat
native appearance selection as equivalent to exercising those system settings.
Actual VoiceOver announcements, Tab/Shift-Tab navigation, command shortcuts, live
composited glass and system reduced-effects behavior remain operator checks.

Independent Standards and Spec reviewers checked `ae59f51...8b7dfe0`. Neither found
new concrete correctness, safety or spec issues. Both confirmed that the disclosed
manual gaps must not be counted as completed QA.

A fresh ad-hoc-signed review app was packaged at
`.build/usability-review-p2fjgprt/Tidy.app`, with `.build/Tidy-Usability.app` as its
local shortcut. It uses the same build/resource/signing recipe as the development
app, in a fresh directory to avoid overwriting the possibly running previous review
build. Deep/strict signature checks and all icon representations pass; app ID and
macOS target are unchanged and no test-framework linkage is present. No app was
launched by packaging. The earlier `.build/Tidy.app`, installed app and notarized
DMG were not replaced.

Quit running Tidy, then open the updated review build from this worktree:

```sh
open .build/Tidy-Usability.app
```

Remaining operator checks before merge:

1. With a disposable folder, use Tab/Shift-Tab and the documented shortcuts to
   reach navigation, the request field, settings, task/cancel controls and Details.
2. Use VoiceOver to review names, roles, progress counts, error details and recovery
   controls. Check the Ready control identifies Local Model Settings rather than
   announcing only an unexplained status.
3. In system Accessibility display settings, exercise Reduce Motion, Reduce
   Transparency and Increase Contrast, verifying live text/control legibility and
   composited toolbar/sidebar behavior. Native appearance tests are not this check.

**Merge is held** until the remaining operator checks pass or the owner explicitly
decides how to track/defer them. The focused pass does not silently close #17 or
authorize notarization or release publication.
