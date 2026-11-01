# #15 — authorized iCloud Drive nonhydration checks

2026-11-01. Based on merged `main` at `f410afb`, on
`ticket/15-icloud-qualification`. **#15 remains open; no hardware is formally
qualified.** This establishes bounded real-provider evidence, not a universal
cloud-provider or final-app qualification.

## Authorized fixtures

The owner authorized creating disposable synthetic files under
`~/Library/Mobile Documents/com~apple~CloudDocs/Tidy Qualification`. Only a newly
created `run-3e2faaffbf31494a8fdd324ee031f970` child was inspected. No personal
provider files or sibling folders were enumerated or opened.

Four synthetic TXT files were created, including a nested pair. Foundation
reported all four as ubiquitous, uploaded, current and not uploading/downloading.
Only then were the two designated placeholder files evicted with
`FileManager.evictUbiquitousItem(at:)`, removing their local copies, not their
iCloud originals. No manual Finder action or system-wide sync setting changed.

| Relative path | Initial uploaded state | After eviction and all checks |
| --- | --- | --- |
| `cloud-only.txt` | Current, locally present | `SF_DATALESS`, NotDownloaded, not downloading |
| `downloaded.txt` | Current, locally present | Current, not dataless/downloading; original bytes preserved |
| `Nested/nested-cloud-only.txt` | Current, locally present | `SF_DATALESS`, NotDownloaded, not downloading |
| `Nested/nested-downloaded.txt` | Current, locally present | Current, not dataless/downloading; original bytes preserved |

These are actual iCloud placeholders, not ordinary files with marker names.
After eviction, the placeholder contents were never opened, read or hashed.
State observations use `lstat` and Foundation resource metadata only. Initial
synthetic payload hashes were recorded before eviction. Downloaded controls were
confirmed local before their content was read.

## Checks and results

The existing opt-in real-provider test passed: read-only folder selection skipped
the direct placeholder as `cloudOnly`, kept the downloaded control eligible, and
observed unchanged placeholder state after two seconds.

A second opt-in integration test and a small same-executable child-process worker
now cover:

1. Actual write-grant folder selection and fresh inventory: direct cloud-only
   file skipped; only the direct downloaded file eligible.
2. Refresh through `restoreFolder()`, the workspace's actual refresh path:
   eligibility unchanged.
3. Explicit recursive planning through the production coordinator: both downloaded
   files appear in the plan, both cloud-only files are skipped as `cloudOnly`.
4. Process exit and two fresh invocations restoring the saved security-scoped
   bookmark: refresh and recursive planning pass again without reselection.
5. After each process, both placeholders remain dataless, NotDownloaded and not
   downloading; downloaded controls retain their original bytes and local state.

The recursive task uses a controlled metadata-only model response. No file moves,
renames, undo or content-based naming were executed in iCloud. The worker creates
and restores real bookmarks; it does not fake provider flags. Temporary settings
and bookmark records are outside the sync folder and are removed afterward.

**Full debug and hosted optimized suites passed with both provider tests enabled,
not skipped:** 125 coordinator, 16 model, 2 worker and 18 workspace functions
reported. The hosted harness checked all 125 discovered coordinator functions
reported. Final independent metadata observations still showed both placeholders
cloud-only and both controls current. Lint and diff whitespace checks passed.

The first optimized run failed because the new worker path was inferred relative
to the packaged test bundle, where the executable was not installed. The existing
provider test passed in that run. An explicit `TIDY_PROVIDER_TEST_WORKER` path was
added using the existing recovery-worker convention; the complete optimized rerun
passed. That failed harness run is retained, not reported as product hydration.
No production behavior change or new dependency was needed.

## Reproduction

Use **only separately authorized, disposable real iCloud fixtures** with the four
names/layout above. Upload all files before evicting the placeholder pair, then
confirm provider metadata rather than opening them. Do not repoint this test at
personal sync files or fabricate a placeholder by changing a filename/flag.

```sh
export TIDY_PROVIDER_FIXTURE_ROOT="/absolute/path/to/authorized/disposable/run"
export TIDY_PLACEHOLDER_PATH="$TIDY_PROVIDER_FIXTURE_ROOT/cloud-only.txt"
export TIDY_DOWNLOADED_PATH="$TIDY_PROVIDER_FIXTURE_ROOT/downloaded.txt"
swift test --disable-automatic-resolution --filter NativePlaceholderTests
swift test --disable-automatic-resolution
bash scripts/release-tests.sh
bash scripts/lint.sh
git diff --check
```

Without opt-in environment variables these real-provider tests remain skipped;
ordinary fixtures cannot establish this gate. `TIDY_PROVIDER_TEST_WORKER` is set
by the hosted optimized script; normal tests find the sibling worker executable.

Local raw evidence is retained under `.build/icloud-qualification/`:
`fixtures.json`, `initial-provider-test.log`, `provider-expanded.log`,
`debug-full.log`, the final `debug-full-final.log`, the failed `optimized-full.log`, the passing
`optimized-full-final.log`, and metadata-only `after-expanded-state.json` and
`final-provider-state.json`. Ignored artifacts alone are not published evidence;
the bounded results are recorded here and the opt-in tests are repeatable.

## Limits and remaining gates

- This qualifies the observed coordinator inventory/refresh/recursive-plan and
  same-worker-process restoration paths for this real iCloud fixture on M4 Max,
  36 GB, macOS 27.0.1. It is not a native GUI/final-signed-app relaunch check.
- Observed before/after flags and a delayed check are not continuous provider
  network monitoring or a universal guarantee against every transient download.
  No independent network attribution was captured.
- No other sync provider, cloud-only directory subtree, content-inspection task,
  mutation/undo under sync contention, offline provider, provider error or large/
  slow provider inventory was qualified here.
- TCC revocation, independent naming review, minimum hardware/macOS, sustained
  memory pressure, genuine production model replacement and the remaining native
  privacy/error matrix are unchanged. Existing manual-check deferrals remain.
- Synthetic fixtures are retained in the authorized run folder for repeatability:
  two cloud-only files and two downloaded controls. No user files, source model,
  installed Tidy state, global permissions, CI or release changed.

See [the earlier remaining-host matrix](stable-v1-remaining.md) for other gates.
Do not check off the aggregate safety/provider acceptance criterion or close #15
solely because this bounded real-provider run passed.
