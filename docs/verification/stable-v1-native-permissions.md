# #15 — installed-beta native folder authority checks

2026-10-31. Actual installed `/Applications/Tidy Beta.app`, version 0.1.0,
build 2. Signed provenance identifies source
`6bcb430a8680d22d36ec63a64e281f3368dea80b`, experimental beta
`v0.1.0-beta.1`. Deep strict signature verification passed before launch.
Installed executable SHA-256:
`45f9e5467ce27ae49e1b2a35c65b14e5d1111252f7701628db0744b995214e8e`.

Host: M4 Max / 36 GB / macOS 27.0.1 (`26A434`). This is observed native
behavior on one configuration, **not formal hardware qualification**.

## Method and fixture

Used `agent-desktop` 1.0.2 (JSON envelope 2.5), with the owner's explicit
permission for clicks/keystrokes in Tidy and relevant permission settings.
Accessibility and Screen Recording permissions were already granted. The owner
manually completed the first read-selection picker after automation could not
reliably navigate it. Later native picker buttons were operated semantically.

Only disposable synthetic files were changed:

- `Selected/notes.txt`, 56 bytes.
- `Selected/receipt.txt`, 37 bytes.
- `Selected/.hidden-check`, excluded from tasks.

Local fixtures, original SHA-256 values, original directory mode and results are
retained under `.build/native-permissions/run-xhxetama/` in this worktree.
The initial blocked attempt remains in `attempt.json`; completed observations are
in `results.json`. No personal-file task, model download, history clearing,
provider fixture, TCC reset, notarization or publication was performed.

## Observed results

| Check | Result and evidence |
| --- | --- |
| Native read grant | PASS: owner selected the fixture; agent observed its exact absolute path, two eligible text files and the skipped hidden fixture. |
| Read bookmark after actual relaunch | PASS: graceful process exit verified for PID 73067; PID 73458 restored the same fixture and inventory without another picker. Original paths and bytes matched the baseline. |
| Read grant does not authorize writes | PASS: actual `Sort by type` submission produced “Select the folder with Grant Write Access before sorting or undoing. An old read grant is not write authorization.” No file names or bytes changed. |
| Picker cancellation | PASS: semantic Cancel closed the native read picker; a subsequent surface listing was empty. Existing fixture selection and file bytes remained intact. An earlier Escape result alone was inconclusive and is not treated as evidence of cancellation. |
| Native write grant and sort | PASS: native “Select a folder to organize” picker granted access to Selected. Exact absolute path and “Write access granted for this folder” were observed before execution. Sort reported two changed, one skipped, zero failures; only the two text files moved to Documents with their names and SHA-256 values preserved. |
| Write bookmark, history and undo after relaunch | PASS: PID 73458 exited gracefully; PID 73645 restored the folder. History selected the two-file fixture task and its exact before/after paths. Without another grant, native Undo Task reported “2 of 2 recorded files undone.” Both originals and all hashes were restored, hidden file untouched, empty task-created Documents removed. |
| Actual filesystem access denial | PASS: temporarily changed only the owned Selected directory to mode 000. Native Refresh cleared the inventory and displayed “This folder is unavailable or access was revoked. Select it again to grant access. Tidy has not inspected another location.” No task composer remained available against the old inventory. |
| History while access is denied | PASS: History remained reachable for the fixture; task/file undo were disabled, with an explicit original-folder access requirement. This task was already undone before denial; this is not evidence of an attempted undo mutation under denied access. |
| Original-folder regrant after denial | PASS: restored the exact original filesystem mode, then used native “Grant Original Folder Access…” and Grant Write Access for Selected. History returned to “0 recorded changes · 2 undone” with the file-restored explanation. No operation resumed automatically. |
| Final integrity | PASS: exact original file set, all SHA-256 values and original directory mode restored. |

The Organize UI's access label after relaunch said access would be checked before
changes, rather than repeating the earlier granted label. The successful actual
Undo Task without regrant establishes restored write authority here; a label
alone is not used as proof.

## Follow-up: access loss while completed changes await undo

On the owner's request, repeated the same two-file sort in the installed beta
(PID 82574), leaving both changes completed and **zero undone**. Independently
verified the sorted paths and original SHA-256 values before removing access.

1. Changed only the owned Selected directory to mode 000 while History still
   offered Undo Task. Invoked that native action without first refreshing away
   the enabled control, exercising the operation's own authorization check.
2. Observed “Undo stopped” with the write-grant requirement and **0 of 2 recorded
   files undone**. History remained available; task/file undo became disabled
   and original-folder regrant was offered. The inventory-refresh warning also
   explicitly reported the unavailable folder.
3. Restored the exact original directory mode. Independently checked that both
   files remained under Documents with their original names and SHA-256 values:
   the denied undo had made no file changes.
4. Used native **Grant Original Folder Access…**, then Grant Write Access for
   Selected. History returned to **2 recorded changes · 0 undone**, with the
   exact fixture before/after paths and enabled undo actions.
5. Before invoking undo again, independently verified both files still occupied
   the sorted paths with unchanged hashes. **Regrant did not silently resume
   the failed undo.**
6. Explicitly invoked native Undo Task. The UI reported **2 of 2 recorded files
   undone**. Independently verified the exact original file set, all SHA-256
   values, untouched hidden fixture and removal of the empty task-created
   Documents folder. Original directory permissions were also restored.

**PASS for this POSIX access-loss/regrant/pending-undo sequence.** This extends
the initial denial check, where the task had already been undone. Local evidence
is retained separately in `pending-undo-access-loss.json` beside the original
results; it does not overwrite the earlier observations. No application source
change was needed. The test-launched app was closed after verification.

## Follow-up: different directory at the same recorded path

Used the same installed beta and owned fixture (PID 82958). A new native sort
completed two moves; History showed **2 recorded changes · 0 undone** for the
exact fixture paths. Verified both destination SHA-256 values independently.

1. Moved the original Selected directory to the sibling HeldOriginal, preserving
   its directory identity and pending sorted files. Created a different Selected
   directory at the recorded path. Recorded the distinct directory inodes and
   used the same destination names (`Documents/notes.txt`,
   `Documents/receipt.txt`, plus `.hidden-check`) with deliberately different
   contents. The replacement therefore did not rely on an absent destination
   tree or occupied original filenames to make an unsafe undo fail.
2. Through Organize's native write picker, explicitly granted the replacement
   Selected folder. No organizing task was submitted against that replacement.
   Returning to History left the old task at **Needs attention · 2 recorded
   files**, with task/file undo disabled and an original-folder grant requirement.
3. Used **Grant Original Folder Access…** but deliberately granted the replacement
   at the old path again. Undo remained disabled with the same original-folder
   requirement: the grant did not make the different directory the recorded root.
   Independently verified the held original still contained both pending sorted
   files with their original hashes and every replacement canary remained intact.
4. Attempted to navigate the native picker's Where control to the parent so the
   renamed original could be selected. The automation actionability check timed
   out **without delivery**. Canceled the picker and confirmed no open surfaces.
   This is not a pass for regranting an original at a different path.
5. Retained the replacement under ReplacementRetained, then moved the **same
   original directory identity** back to Selected. No files were deleted or
   copied over either fixture. Native **Grant Original Folder Access…** and
   Grant Write Access now restored **2 recorded changes · 0 undone**, with undo
   enabled and the completed-file explanation.
6. Independently verified all original sorted hashes and every replacement
   canary before undo: regrant had not resumed an operation. Explicit native
   Undo Task then reported **2 of 2 recorded files undone**. Final independent
   checks confirmed the original directory inode and permissions, exact original
   file set and SHA-256 values, empty task-created Documents removal, and the
   replacement's unchanged inode, complete tree and distinct contents.

**PASS for same-path replacement rejection, wrong-folder regrant not authorizing
old undo, and recovery after restoring the actual original directory.** The
disabled actions were observed, not force-invoked. Original files are restored;
the unchanged replacement is retained separately for inspection. Detailed local
state and results are in `replacement-identity.json`, without overwriting either
earlier run. No production fix was needed. The test-launched app was closed.

## Focused retry: regrant and undo while the original remains renamed

The owner authorized one keyboard-navigation retry, with manual selection as the
fallback if automation failed. The retry succeeded without that fallback, using
the same installed beta (PID 92349) and a new set of retained test artifacts.

1. Native sort completed two moves in Selected. Independently verified the
   sorted file hashes, moved the original directory to RenamedOriginalRetry,
   and created another different-identity Selected replacement with matching
   destination names and distinct contents. Earlier replacement artifacts
   remained untouched.
2. Explicitly granted the replacement through the native write picker. History
   correctly required original-folder access and disabled task/file undo for
   the old task. No task was submitted against the replacement.
3. Focused Tidy's History window **before** opening Grant Original Folder Access.
   After observing the native modal picker, sent an unscoped physical
   Command-Shift-G shortcut. A fresh snapshot showed the Go to Folder text field.
   Set it to the exact RenamedOriginalRetry path, sent Return, and verified
   that the picker's Where control read **RenamedOriginalRetry** before selecting
   Grant Write Access. This worked where the earlier Where-control navigation
   and app-PID-targeted shortcuts had not; it is not a general claim about other
   modal dialogs or keyboard accessibility.
4. History returned to **2 recorded changes · 0 undone**, with task/file undo
   enabled. Independent inode and SHA-256 checks confirmed the original still
   occupied **RenamedOriginalRetry**, both files remained sorted there, and
   the replacement remained at the recorded Selected path with its distinct
   contents unchanged. Regrant had not resumed undo.
5. Explicit native Undo Task reported **2 of 2 recorded files undone**. Before
   restoring any directory names, independently verified the original
   basenames and all SHA-256 values **under RenamedOriginalRetry**, the original
   directory inode/mode, and removal of its empty task-created Documents folder.
   The Selected replacement's inode, complete tree and distinct file contents
   were unchanged. History continued displaying the recorded old absolute paths;
   these independent checks establish the actual mutation target, not those
   historical labels alone.
6. Closed the test-launched app. Only **after** the renamed-path recovery passed,
   retained the replacement as RenamedPathReplacementRetained and restored the
   same original directory to Selected. Verified the original file set,
   SHA-256 values and directory inode/mode again, as well as the unchanged
   replacement artifacts from both runs. No fixture files were discarded.

**PASS for native regrant and explicit undo while the original remains renamed
and a different folder occupies its recorded path.** Local evidence is in
`renamed-path-retry.json`; the earlier failed-navigation record is preserved.
No production code or release artifact change was needed. This is one bounded
same-volume/configuration observation, not universal bookmark, volume,
sandbox/TCC, provider or keyboard-accessibility qualification.

## Automation limitations and remaining gates

Opening modal pickers sometimes returned `APP_UNRESPONSIVE` / uncertain delivery
even though the picker appeared. Scoped headed keyboard/window commands also
reported `global_window_inventory_unstable` / `frontmost_window_join` timeouts.
These were handled by inspecting fresh state, not blindly repeating mutations.
Semantic Cancel and Grant Write Access succeeded when the live picker was
observable. Native results and independent filesystem hashes, not action success
envelopes, establish the passes above.

**Mode 000 is actual POSIX permission denial, not macOS sandbox/TCC revocation.**
No privacy permission setting was changed. System Settings navigation was inspected
but did not yield a reliable per-fixture revocation action; its search was cleared
and the app closed afterward. No global reset or broader access was substituted.
Sandbox/TCC revocation and stale/unavailable volume cases remain unverified.
Same-path different-identity reselection and renamed-original regrant/undo are
covered by the bounded follow-ups above, not every replacement, bookmark-staleness
or volume scenario. The pending-undo follow-up covers **POSIX** access loss while
changes remain completed; it does not establish that result for sandbox/TCC
revocation.

This native automated check does not qualify VoiceOver, physical keyboard-only
navigation, independent naming quality, real providers, other hardware/OS versions
or pressure/resource bounds. It does not reopen the owner's deferred formal undo
cancellation, native-offline or diagnostic-export wizard checks. No production
source or release artifact was changed by this follow-up.

Keep #15 open. Accessibility remains #18. Supported hardware: NONE qualified.
