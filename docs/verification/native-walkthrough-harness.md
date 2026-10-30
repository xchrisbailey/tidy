# Native walkthrough: Finder metadata false failure

During read/write grant checks, the local fixture checkpoint failed exactly with
`missing=[], unexpected=['.DS_Store'], changed=[]`. The agent reproduced this on
the operator's disposable `basic` fixture; no original file was missing or changed.
A separate generated-fixture regression reproduced the same metadata-only failure
before the checker correction. This was a fixture-harness mismatch, not evidence
of a Tidy file mutation or a successful native grant test.

The ephemeral `.build/native-acceptance/fixture-check.py` now tolerates only newly
created, single-link regular files whose basename is exactly `.DS_Store`.
Existing baseline entries remain hash-protected. No metadata, original fixture,
manifest, or operator observation was deleted or rewritten.

The regression checks pass for root/nested metadata, sorted results, partial
cancellation and content naming. Negative controls still reject symlinks, hard
links or directories named `.DS_Store`, other unexpected hidden files/folders,
changed hidden-file bytes, missing originals and altered/deleted baseline
metadata. The operator's original checkpoint now passes under that policy.
Shell syntax also passes. Application sources and the signed native artifact are
unchanged; Swift suite/packaging reruns are unnecessary for this checker-only fix.

Stop the currently parsed wizard with Ctrl-C and rerun:

```sh
bash .build/native-acceptance/native-checks.sh --continue-native
```

The recorded READ_GRANT/INTENT failures remain until fresh operator observations
supersede them with attempt history retained. A filesystem checkpoint pass does
not automatically mark native permissions/clarification checks passed. Public
release qualification remains incomplete.
