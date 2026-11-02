# #15 — folder birth-time drift investigation

2026-11-01. Follow-up to the [permission-revocation attempt](stable-v1-permission-revocation.md),
based on `dc5ea7ee`. **The ordinary undo limitation is reproduced, not fixed.**
TCC/sandbox revocation remains blocked and no stable-v1 gate is completed here.

## Finding and minimized reproduction

The timestamp used by Tidy's strict identity check can change on this host even
when Tidy is absent. Raw POSIX-created Documents directories changed birth-time
nanoseconds after creation while retaining device/inode and birth seconds. The
changed values exactly matched a Unix-seconds floating-point `Double` round-trip.
Equivalent local-worktree controls stayed stable.

This rules out Tidy journal encoding as a necessary cause. It does **not** identify
the writer or distinguish a background metadata writer from an OS/filesystem
normalization path. No provider, backup tool or macOS service is blamed without
attribution evidence. Timing was intermittent; do not infer all Documents folders
or Macs behave this way.

Only newly created synthetic paths inside the already authorized
`~/Documents/Tidy Qualification` and ignored worktree evidence were used.

1. A coordinator harness created one TXT file, sorted it through the production
   recovery worker, and SIGKILLed after completion persistence. Fresh same-worker
   recovery and independent exact `stat` comparison were sampled immediately,
   after two seconds and after eight more seconds.
2. The local control stayed completed with matching identities. The Documents
   fixture initially matched, then its root and sorting-folder birth nanoseconds
   changed; recovery returned uncertain. File identity stayed equal.
3. Removing Tidy, the journal, file moves, bookmarks and SIGKILL still reproduced
   drift: a standalone program performed raw `mkdir(0755)`, then only `lstat`
   observations once per second. Its initial integer stamp also survived a
   Codable JSON round-trip exactly.

The first coordinator attempts ran before the freshly written Documents source
settled. Production validation skipped it as stale without changing it, so no
completion checkpoint was reached. Those are not birth-drift reproductions. A
two-second initial settling delay allowed the completed/recovery mismatch above.
That separate stale-source refusal was not bypassed.

| Raw mkdir experiment | Documents result | Local control |
| --- | --- | --- |
| Mode 0700, 21 observations | No drift observed in that run or later observation. | No drift. |
| Mode 0755, 21 observations | First drift after 2 s: `368853620` → `368853569` ns. | No drift. |
| Mode 0755, repeat, 9 observations | First drift after 3 s: `298876538` → `298876523` ns. | No drift. |
| Mode 0755, repeat, 9 observations | No drift during that run or later observation. | No drift. |

The coordinator reproduction's root changed `292309327` → `292309284` ns;
the sorting folder changed `324011973` → `324012041` ns. Device/inode and birth
seconds remained unchanged. Each changed value above is exactly:

```swift
Int64(((Double(seconds) + Double(ns) / 1e9) - Double(seconds)) * 1e9)
```

The original native failure's `616944000` → `616944074` ns has the same signature.
These observations support a precision-conversion mechanism outside the journal;
they are not continuous syscall tracing or proof of a specific responsible process.
No root tracing, TCC database access, broad process inspection or personal-file
enumeration was used.

## Why undo refuses; no tolerance patch

`FileIdentity` deliberately includes device, inode and exact birth time, so inode
reuse alone cannot impersonate an old file/folder. Undo, recovery and write-grant
validation compare these identities. The observed metadata changes therefore
invalidate the recorded identity even though the files themselves remain intact.

Root drift fails write-grant validation; sorting-folder drift fails the recorded
folder check. Both paths stop without moving files or changing the durable
journal. This is consistent with current fail-closed policy, but leaves a real
**best-effort undo limitation** on the observed host/path—not successful undo
qualification.

Rounding birth times, accepting a tolerance, ignoring birth time or trusting
unchanged bytes would broaden what counts as the original identity. That needs
an explicit identity-policy decision with replacement/inode-reuse safety evidence,
not an incidental qualification patch. No production behavior was changed here.
Clearer user guidance may also be useful; the generic identity warning remains.

## Deterministic integration coverage and verification

`undoRejectsNanosecondBirthTimeDriftWithoutChangingFiles` simulates the observed
metadata-only drift using `setattrlist(ATTR_CMN_CRTIME)` on a real temporary
directory after a successful production sort. Root and destination cases verify:

- Device/inode and birth seconds stay unchanged; nanoseconds differ by exactly
  74 (subtracting near the second boundary).
- Repeated recovery reports uncertain without mutating history.
- Task/file undo refuse (`writeGrantRequired` for root, `uncertainIdentity` for
  destination); sorted bytes/paths, sorting folder and exact journal bytes remain.

This tests the current safety response, **not automatic recovery from legitimate
metadata drift**. The first focused run incorrectly expected uncertainIdentity
for root drift; it hit the earlier write-grant check. Correcting the expectation
to the actual distinct safety boundary passed. No production check was weakened.

Ten focused repetitions passed **20 controlled metadata-drift cases**. Full debug
and hosted optimized suites passed: **126 coordinator, 16 model, 2 worker and 18
workspace functions reported**. The hosted harness confirmed all 126 discovered
coordinator functions reported. Both real-provider opt-in tests were skipped;
the earlier enabled [iCloud qualification](stable-v1-icloud.md) is not replaced
by these ordinary fixtures. Lint and diff whitespace checks passed.

```sh
swift test --disable-automatic-resolution --filter undoRejectsNanosecondBirthTimeDriftWithoutChangingFiles
swift test --disable-automatic-resolution
bash scripts/release-tests.sh
bash scripts/lint.sh
git diff --check
```

## Evidence, cleanup and open work

Local raw evidence under `.build/permission-revocation/`: the four
`birth-drift-*.log` harness attempts; `birth-drift/*/results.json`; `raw-posix*.log`
observations; exact-stat inspector and standalone probe sources; focused logs
(including the failed expectation), focused-repeat, debug-full and optimized-full
logs. These ignored diagnostic harnesses are not production code or published
artifacts; recorded outcomes and the integration test are repository evidence.
Temporary worker instrumentation was removed.

Twelve exact recorded probe fixture directories were removed after verifying
synthetic payload or emptiness. No broad recursive deletion was used. Worktree
worker roots, evidence/journals and the restored original permission-test fixture
remain retained. Probe cleanup is not app undo.

Remaining decisions/work:

1. Attribute or characterize the normalization mechanism if broader support claims
   require it; the responsible process remains unknown.
2. Decide whether to retain this documented best-effort limit, improve recovery
   guidance, or design stable identity handling that tolerates metadata rewriting
   without accepting replacements. Do not silently relax the identity contract.
3. Establish a genuine scoped permission-revocation method independently. This
   experiment does not close that gap or change owner deferrals.
