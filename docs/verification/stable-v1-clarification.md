# #15 — clarification failure and prompt fix

2026-11-02. Follow-up to the [native matrix](stable-v1-native-resume.md), using the
same approved local candidate model and synthetic fixtures. **The three observed
native clarification failures are fixed in the local worktree. #15 remains open.**

## Reproduction and cause

Added a packaged real-model/coordinator regression command:

```sh
env NSUnbufferedIO=YES bash scripts/model-smoke.sh --clarification-only
```

Before the fix, all three original requests failed with `invalidResponse`:

- `Organize these files`: unsupported envelope omitted request-clause coverage;
  its replacement was an actionless plan with an unsupported clause.
- `Sort only notes.txt by type`: model first tried an unauthorized substring
  selection, then dropped that restriction. Both were rejected.
- `Rename these files`: model twice emitted an empty rename plan.

Synthetic response capture established a prompt/schema-guidance failure, not a
lost native text binding or a UI mapping of a valid clarification into an error.
The reproducer initially needed the existing smoke harness's security-scoped
bookmark resolution; its first `writeGrantRequired` attempt was not the target
failure and is not counted as a product result.

The planning prompt already required clarification but primarily demonstrated
successful plans. Added explicit vague-request/exact-file guidance and complete
clarification examples with exact clause coverage, empty rules/selection/files and
a specific resubmission question. A first prompt probe fixed vague organizing and
renaming but not exact-file selection; adding its complete envelope example fixed
that remaining reproduction. No validator, retry budget, selection authority,
file-operation logic or UI error fallback was weakened or replaced.

Temporary raw-response tracing was removed. Final smoke failures unload the model
and exit nonzero rather than leaving an uncaught error. The retained regression
exercises the actual candidate, not a stub returning a desired clarification.

## Regression and native results

The final packaged command passes the original three requests plus `Please
organize my files`, `Rename all files` and `Sort only report.txt by type`. Each must
return a nonempty clarification and leave the original fixture set/bytes intact.
It then requires an explicit `Sort by type` plan with two moves and no renames,
executes it, verifies reopened undo and original bytes, and checks mixed deletion
refusal. Expanded and final runs both passed with network denied by the existing
packaged-smoke wrapper; no model download occurred.

Rebuilt and deep-strict-signature-verified the isolated **Tidy Matrix Test** bundle,
preserving its previous profile and 105 undone history entries. APFS-cloned the
approved source weights, then physically typed each original request and verified
the actual field value before submitting against exact owned `Clarification`:

| Request | Native task-result observation |
| --- | --- |
| Organize these files | Asked how to organize them and requested an exact sorting criterion or renaming rule. |
| Sort only notes.txt by type | Explained exact-file selection is unsupported and asked about an extension or quoted name-substring filter. |
| Rename these files | Asked which rename rule to use, with case/separator/prefix/content choices. |

All three displayed edit/resubmit instructions and **No files changed**. Fresh
task-result snapshots—not the window title or action envelopes—established the
questions. All fixture paths/hashes and the 105-entry undone journal were unchanged
before resubmission. Explicit `Sort by type` then completed two moves; exact task
History showed two recorded changes, zero undone. Native Undo Task reported **2
of 2**, restoring original filenames/bytes and removing the empty sorting folder.

Native Settings Remove Model showed **No installed model**; the cloned revision
was absent and both unrelated canaries remained exact. Process `67238` exited
gracefully with confirmation; only its temporary registration was removed. History
is retained with **107 operations, all undone**. All original fixtures and approved
source-model hashes were rechecked unchanged. A transient picker-helper failure
was resolved only after inspecting the actual modal and exact selected path.

## Broader verification and limits

- Full debug and hosted optimized suites passed with the previously authorized
  provider and diagnostic identity opt-ins enabled: **129 coordinator, 16 model,
  2 worker and 18 workspace functions**, no skipped tests.
- The full packaged real-model smoke passed, including existing metadata/content
  tasks and safety checks. App packaging, lint and whitespace checks passed.
- Unchanged 32-case corpus replay: **21/22 descriptor-usable upper bound**, **21/24
  cryptic-useful upper bound**, seven abstentions, two unchanged, one skipped, zero
  errors. Known S03 `Faclura` error remains. All bytes/reopened undo checks passed.
  No rubric, threshold, denominator or model revision changed.
- This replay's 100-file task took **6.238 s including 1.996 s loading**; the separate
  content-heavy 12-file task took **11.785 s excluding completed loading** on this
  host. These are observations, not minimum-hardware or performance-regression
  guarantees. Independent semantic/human review remains outstanding.

The fix improves demonstrated model behavior; it does not prove clarification for
every paraphrase or replace strict fail-closed handling of invalid future output.
The specific earlier native clarification gap is now observed passing. Volume-
incarnation proof, genuine TCC revocation, independent naming review, other hardware/
macOS, sustained pressure, production-model replacement, #16/#18 and the existing
formal owner deferrals remain unresolved. Nothing committed, pushed, merged or
released.

Evidence remains under `.build/native-matrix/`: `clarification-red.log`, initial
prompt-probe/green/expanded/final logs, native task-result/grant/resubmission
snapshots and `clarification-native-results.json`, full debug/optimized/model/corpus
logs and app-build log. Initial failures remain historical evidence.
