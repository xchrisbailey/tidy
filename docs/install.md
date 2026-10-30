# Tidy: unqualified development installation and setup

**PUBLIC RELEASE BLOCKED. Supported hardware: NONE qualified.** This guide is for
local, disposable qualification only, not an invitation to download a public
release. Signing does not establish safety or hardware support. #15 and #16 stay
open. Use backed-up synthetic files, not your real Downloads/Desktop or sync data.

## Mac requirements and cost

The current build is native arm64 (Apple silicon), targets macOS 14+, and
provisionally enables model setup from 16 GB unified memory. These are build/runtime
bounds, **not qualified minimum requirements**. Intel is not built. The observed
M4 Max / 36 GB / macOS 27.0.1 results do not qualify that Mac, macOS 14, or 16 GB.
Independent quality, native GUI, recovery repeatability and hardware gates remain.

The intended app is free and account-free: no payment, subscription, trial limit,
App Store path or cloud inference. First model setup needs an internet connection
and explicit download consent, but no Hugging Face account or token.

## Install a future approved direct download

These steps must be verified on the **final notarized, qualified artifact** before
publication. They are not completed acceptance checks for today's candidate.

1. Obtain the ZIP and its independently published SHA-256 from the approved HTTPS
   distribution location (not selected yet). Compare with `shasum -a 256 PATH.zip`.
2. Expand it in Finder, read its bundled warnings, then copy the app to Applications
   in a clean test user. Quit other Tidy builds first. The candidate has the explicit
   name **Tidy Unqualified Development.app**; it is not a release.
3. Open from Applications. Verify the expected identified developer and ordinary
   Gatekeeper behavior. The candidate is not notarized and may be blocked. **Stop
   and record the failure; do not remove quarantine, disable Gatekeeper, or use an
   “Open Anyway” bypass as installation evidence.**
4. Choose **Local Model Setup…**. Review the size and consent before Download / Resume.
   Readiness requires size/SHA-256 verification and local native inference, not just
   a completed transfer. Offline first-time setup without installed weights cannot
   work. There is no cloud/Apple built-in model fallback or supported manual import.
5. Select a disposable local folder in the native picker, granting read/write
   access only to that folder. Try a clear request such as “Sort by type.” Clear
   requests execute without preview; ambiguous requests ask for clarification.
   More than 100 changed files require confirmation of counts. Read skipped,
   abstained, failed and conflict explanations; do not repeatedly retry a busy or
   interrupted mutation as a workaround.

Candidate and development bundles deliberately retain `dev.xchrisbailey.Tidy` for
real sandbox/bookmark qualification. They share app storage; a renamed app is **not
an isolated install**. Do not replace a working installation or delete its container.

## Model download, offline operation and storage

Current candidate: `mlx-community/Qwen3-4B-Instruct-2507-4bit`, revision
`50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b`, Apache-2.0. Allowlisted download:
**2,278,969,697 bytes (~2.28 GB / 2.12 GiB)**, separate from the app ZIP. Setup
conservatively reserves `3 × download + 512 MiB` = **7,373,780,003 bytes (~7.37 GB)**
for temporary copies and safety margin. Old versions, app, history and other disk
use are additional. Storage is checked again before transfers, not guaranteed forever.

Pause retains verified files/resume data. Resume needs consent again and may restart
the current file. Cancel and Remove Partials stops transfers before deleting
partials; installed models remain. **Local Model Storage…** shows installed revision
bytes, incomplete transfers and active status; Refresh Storage updates the view.
Remove… confirms deletion; removing the active model disables tasks until another
model is checked/installed. Replacement retains the working model until verification
and native inference pass; old versions remain until explicitly removed.

After setup, **Check Installed Model Offline** verifies an installed model without
downloading. Tasks use that local model offline. Qualify a real task with networking
disconnected after a real app relaunch; diagnostic network-denial results alone do
not establish this GUI workflow.

Models live at the app's Application Support `Tidy/Models`, folder grants and
recovery records at Application Support `Tidy`. In the sandbox this is normally
`~/Library/Containers/dev.xchrisbailey.Tidy/Data/Library/Application Support/Tidy/`.
Developer diagnostic `~/Library/Application Support/Tidy/QualificationModels` is
separate and is **not bundled or automatically imported** into a clean user's app.
Use in-app controls rather than editing/removing active storage files.

## Privacy, history and undo

File names, contents, instructions and model output are processed on the Mac.
Only consented model setup uses a provider connection; the provider sees normal
download metadata such as IP address/model URLs, not task inputs. There is no
automatic telemetry, analytics, crash uploader, account or support submission.
Private Diagnostics exports only on explicit user action; inspect before sharing.
OS swap, system logs/crash diagnostics and secure erasure are not covered by this
app-level retention promise.

**Existing sync services can transmit renames/moves in already-synced folders.**
Local inference does not disable iCloud/Dropbox/other sync. Tidy skips detected
cloud-only files rather than hydrating them; real-provider nonhydration remains an
unverified gate. Do not infer qualification from local marker-file tests.

Undo History keeps original/resulting paths and recovery information on this Mac,
not document excerpts, until **Clear History…**. The displayed recovery-record bytes
exclude model storage, grants and lock bookkeeping. Clearing requires confirmation,
permanently loses Tidy undo, does not reverse changes or touch user files, and keeps
models and folder grants. Removing the app alone does not promise removal of its
container/history/models. Decide on undo first and use the controls before uninstalling.

Undo Task / Undo File is best-effort, not a backup. It needs the same identifiable
file, available volume and original-folder write grant. Occupied original locations
are never overwritten; unavailable/changed identity or other conflicts can prevent
undo. Grant Original Folder Access… can restore authorization, not missing bytes.
Relaunch reconciles actual files; interrupted mutations never automatically resume.
Only empty task-created folders may be cleaned up. Back up before organizing.

The intermittent recovery `.busy` observed in qualification is not diagnosed or
fixed. Do not claim all safety checks passed or try mutation retries to hide it.
See [distribution gates](distribution.md) and [corrective evidence](verification/qualification-v1-corrective-results.md).
