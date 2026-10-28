# #8 — explicit recursive source scope

2026-10-28. Provisional implementation; native release gates remain open and the
issue was not closed. Started clean on `ticket/8-recursive-scope` at requested
integration base `f0a1a6f`. `git merge --no-edit integration/tidy-v1` reported
already up to date before final verification.

## Behavior and authority

`TaskCoordinator.planTask(request:model:)` and `PlanCompletion` are unchanged.
Direct children remain the default. Explicit inclusion such as “including
subfolders” or “recursively” inventories eligible descendant files. Negated
inclusion stays direct-only; uncertain, singular/named-subfolder or conflicting
scope asks for a complete clarified request instead of guessing. Quoted filename
or naming literals cannot grant recursive access. The bounded metadata intent
envelope and its existing complete-clause/source-ID validation remain unchanged.

Recursive inventory reuses the existing exclusions at every level, pruning entire
hidden, package, link, incomplete-download and cloud-only subtrees. Hard-linked
files are also excluded. Dataless flags are checked before Foundation resource
metadata; no contents are opened or provider downloads requested. POSIX snapshots
and enumeration use pinned directory descriptors. Foundation has no fd-based
package/provider-resource API: those metadata-only queries use the corresponding
URL, with ancestor identities and the descriptor-relative snapshot rechecked.
Their result never supplies filesystem authority.

Existing folders never become operations. Rename-only files remain in their
original parent. Sorting destinations remain the root or one validated immediate
child of the selected root; the model still cannot supply nested paths. The only
nested destination allowed by executor/journal validation is an inventory file's
captured original parent for an in-place rename. Existing destination folders are
retained; undo cleans only identified empty task-created folders.

Inventory items, planned changes and durable operations carry optional original
ancestor identities. Original names in recursive operations/history are
root-relative paths; destination names remain single components. Every original
ancestor must have captured authority. The added journal field is optional so
existing direct-child history still decodes. Downstream planners must copy this
authority from inventory into their changes rather than constructing paths or
inventing ancestry. No content-reading permission is implied by these helpers.

Source pinning, inspection, mutation, recovery and undo resolve relative parents
one component at a time with no-follow directory handles. Passing a slash path
straight to `openat`/`renameat` would protect only its last component and is not
used. Source parent and destination identities are rechecked after the durable
pre-move checkpoint, along with source snapshots. Undo also rechecks authority
after its durable intent checkpoint. Exclusive rename and the existing durable
recovery core remain authoritative; unsafe/changed ancestry is an identity
conflict, never permission to follow a replacement link.

All candidates share one 1,000-file ceiling, complete model response, reservation
space, 100/101 confirmation threshold, progress/cancellation run and history.
Traversal additionally fails the whole request beyond 20,000 visited entries,
128 nested levels or the supported relative-path bound; it never accepts a
truncated prefix. Directory enumeration checks cancellation and bounds while
reading, not only after collecting the tree. The native context/output limits
and one complete replacement limit are unchanged.

## Coordinator/filesystem evidence

All added tests use the agreed public coordinator seam with actual temporary
files and scoped bookmarks. Only model responses and durable interruption points
are controlled.

Observed red → green:

1. Explicit recursive type sorting initially returned unsupported. It now moves
   nested duplicate names into root destinations, reserves suffixes globally,
   leaves already-organized files and folders intact, and restores original paths
   and bytes through reopened undo.
2. “Do not include subfolders” incorrectly expanded recursive inventory; the
   one-file direct-only response failed. Explicit negation now leaves nested
   files untouched. The same red/green was observed for “without including files
   from subfolders.”
3. Conflicting “including subfolders but not recursively” reached inference as a
   direct-only task. It now asks for scope clarification before inference.
4. Plural named/quoted subfolder selections reached inference against the whole
   tree. Those limited-scope requests now clarify rather than broadening access.

Additional regression coverage verifies:

- default scope and ambiguity without inference;
- whole hidden/package/download/cloud-marker subtrees, file markers, hard links
  and links back outside the scope, with only one eligible descendant changed;
- nested rename-only operations, preserved parent spelling/date/identifier/
  extension, case-variant reservation, occupied-original undo conflicts and retry;
- source ancestor swaps before execution, immediately before moving and during
  undo intent; destination replacement with an outside link before moving;
- rejection of traversal, absolute and arbitrary nested model destinations;
- recursive 101-file confirmation/counts, stale-source skip, cancellation after
  two completed changes, remaining-file accounting and reopened undo;
- a 1,001-file recursive scope rejected before inference.

## Native offline diagnostic

`bash scripts/model-smoke.sh` passed with the existing approved local model, no
download, `(deny network*)`, and original SwiftPM product reads denied. The signed
diagnostic resolves its own scoped bookmark; this is not NSOpenPanel consent.

The added real-model recursive task used three eligible nested/type-folder files
and one hidden subtree. It produced two moves with reserved collision names,
one already-organized file and one pruned subtree. Existing nested folders and
the destination folder remained. Reopened undo restored every synthetic file's
original bytes/path. One complete run observed recursive task time of 5.522 s; 1,218 prompt /
173 output tokens, 1.306 s prefill and 5.444 s generation. Existing metadata,
combined naming, task-chain undo, oversized-context rejection, native cancellation
and replacement checks also passed.

## Checks and open gates

| Command | Result |
| --- | --- |
| `swift test --disable-automatic-resolution` | Passed: 67 executed core tests and 11 model tests, **78 executed total**; one existing real File Provider test skipped (68 reported core tests). |
| `bash scripts/lint.sh` | Passed strict Swift formatting, three plists and shell syntax. |
| `git diff --check` | Passed. |
| `bash scripts/model-smoke.sh` | Passed complete signed offline diagnostic, including the new recursive task. |
| `bash scripts/build-app.sh` | Passed arm64 packaging, bundled Metal resources, ad-hoc signing and strict signature verification. |

No new dependency, CI, cloud service, model download or primary user documentation
change. Locked dependency resolution fetched approved cached dependencies during
the first build; no approval blocker occurred. The existing upstream MLX resource
bundle mutated-node warning remains nonfatal.

Native GUI tools and real File Provider fixtures are unavailable. Picker/write
consent, interactive clarification and confirmation, visible recursive progress/
cancel, keyboard/VoiceOver, final app sandbox behavior and actual app-process
restart still need manual qualification. Marker fixtures are not proof that a
real provider remains unhydrated; that native gate remains open. Broader recursive
language quality, filesystem/provider variants, concurrent hostile-process race
stress, macOS 14/lower-memory hardware and distribution/archive qualification
are not claimed complete.
