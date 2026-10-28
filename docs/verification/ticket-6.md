# #6 — local-model setup verification

2026-10-28. Provisional implementation; **leave #6 open**. Release hardware/OS and planning-quality gates remain open. No CI was configured or used.

## Candidate and dependency decision

- Artifact: [mlx-community/Qwen3-4B-Instruct-2507-4bit](https://huggingface.co/mlx-community/Qwen3-4B-Instruct-2507-4bit/tree/50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b), revision `50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b`. Eleven runtime files, **2,278,969,697 bytes** in the app-bundled allowlist. Every file has a reviewed raw-content SHA-256 and exact size; no mutable provider metadata or ETag establishes trust during setup.
- Native roots: MLX Swift LM 3.32.3 (`3b339ad6e3b3f44c8121ecff5131c7fd55e075e6`), MLX Swift 0.32.3 (`19601207e9a0de51e03ee6ec0c3c5f3784275075`), swift-transformers Tokenizers 1.3.5 (`48473106a93b2d8dfb114b82f0628ebbb71734e7`). New inference/tokenizer dependencies and the qualification download were explicitly approved by the user.
- Do **not** link MLXGuidedGeneration at this pin: upstream's generated-text-prefix logging is unsuitable for sensitive filenames, and its vendored C++ target has unsafe flags. Neither was patched or silently accepted. Tidy uses the ordinary native TokenIterator, greedy decoding, complete EOS-terminated responses, a bounded token budget, and downstream full-envelope validation. Grammar-constrained generation is not claimed.
- Disable the LM package's default FoundationModelsIntegration trait. No Apple built-in model, cloud service, shell/Python inference, Hub downloader, arbitrary import, or Xet dependency is used. Foundation URLSession handles only explicit setup downloads; CryptoKit handles streaming integrity checks.
- Effective build floor: Swift 6.3 / macOS 14 / Apple silicon. The actual verification machine was Swift 6.4, Xcode selected at `/Applications/Xcode.app`, M4 Max, 36 GB, macOS 27. A successful build here is not macOS 14 execution evidence.

## Redistribution and graph

The community conversion declares Apache-2.0 and identifies Qwen's upstream model and mlx-lm 0.26.2 conversion. Its card does not pin the conversion's upstream revision or provide reproducibility evidence. Tidy does not change the artifact. Bundle the archived upstream Apache license, conversion card/attribution, and dependency notices from `Packaging/Notices`; packaging copies them into the app. No separate upstream NOTICE appeared in the model's file tree.

`Package.resolved` locks the entire graph. The three native roots are MIT/MIT/Apache-2.0 respectively. Transitives: swift-jinja 2.5.2 and swift-huggingface 1.0.0 (Apache-2.0); EventSource 1.5.1 and yyjson 0.12.0 (MIT); swift-collections 1.7.5, swift-numerics 1.1.1, swift-crypto 4.5.2, swift-asn1 1.7.3, swift-syntax 603.0.2 (Apache-2.0 with Swift exception). Copies include Cmlx/MLX, fmt, nlohmann/json, metal-cpp, and resolved source-graph notices. XGrammar notices are included conservatively, but its target is not linked. swift-syntax is resolved for upstream macros; Tidy does not link the Hub macros. `scripts/collect-model-notices.sh` regenerates copies from resolved checkouts and immutable model-license/card URLs.

## Observable lifecycle and local tests

Agreed seam: public observable `ModelSetup` lifecycle, controlled transfers, real temporary storage, and injected native-load boundary. No private-state assertions. Consent and unsupported hardware cannot begin a transfer. Setup checks free storage on both Application Support and URLSession's temporary volume; the conservative reserve is three full artifact copies plus 512 MiB. A 16 GB provisional memory floor is explicitly **not** hardware qualification.

Files stage on the installation volume. Existing/resumed files are rehashed completely. Promotion is a same-volume directory rename only after the complete allowlist verifies. Relaunch rechecks every file and performs local inference before readiness; no persisted ready flag is trusted. Failed native load stays unusable. Restore never uses the network. Cancellation waits for transfer/runtime quiescence before partial cleanup; installed verified files are retained but are not marked ready after cancellation.

Red/green evidence:

1. Consent test failed to compile before lifecycle API existed; minimal implementation made it pass.
2. Verified-load/relaunch test failed before restore/installation support existed; implementation made it pass.
3. Real-URLSession transfer test failed before the transport existed; implementation made it pass.
4. Crucially, the real interruption test then failed because async URLSession cancellation produced **no resume file**. Replaced it with explicit `cancel(byProducingResumeData:)`, waiting for both task completion and resume callback; the test passed. This is real controlled HTTP traffic, not a mocked URLSession.

Coverage includes denied consent, unavailable hardware, low storage, load failure, corrupt same-sized files, rechecking installed files, pause/relaunch/resume, cancellation writer quiescence/cleanup, redirects, invalid resume data, truncated bodies, SHA mismatch, a genuine resumed `206`, ignored Range/changed validator returning `200`, and replacement rather than unchecked append. Completed/resumed files must still pass whole-file hashing. Pause preserves OS resume data when available; expired/missing resume state restarts only the affected file. Progress advances per verified file, not byte-by-byte within the weight file.

## Real native evidence

The user's separately approved qualification download went to `~/Library/Application Support/Tidy/QualificationModels`, not into selected user folders or the normal installation. It used the same lifecycle, immutable manifest, URLSession transport, native runtime, and tokenizer adapter as the app. Initial verified setup including download took 48.864 s. No account was used.

Offline repeat (network denied by `sandbox-exec -p '(version 1) (allow default) (deny network*)'`):

| Measurement | Observed |
|---|---:|
| Full rehash, native load, small readiness generation | 2.130 s |
| Readiness prompt/output tokens | 36 / 5 |
| Readiness prefill / generation total | 0.0710 / 0.1976 s |
| Fixed synthetic rename prompt/output tokens | 65 / 15 |
| Rename prefill / generation total | 0.0443 / 0.2854 s |
| MLX active after generation | 2,264,697,824 bytes |
| MLX cache after generation | 39,764,420 bytes |
| MLX peak after generation | 2,490,338,760 bytes |
| Process physical footprint after load | 2,556,186,800 bytes |
| Process physical footprint after rename | 2,545,193,136 bytes |
| Cancellation to drained Metal work | 0.00917 s |

The fixed, non-sensitive rename returned the exact expected complete JSON operation, decoded and compared in memory. This is a narrow native candidate smoke, **not** proof of production planning quality or execution through TaskCoordinator. A longer generation was cancelled; the task awaited completion and Metal synchronization, and subsequent native inference succeeded. Only counts/timings/memory/status were written to logs—no raw generated output or real filenames. The runtime rejects prompt+output above 8,192 tokens and output budgets above 2,048, and never returns a truncated prefix. Long-context/pressure behavior still needs qualification.

## Remaining gates

- Native GUI unavailable in this agent session: manually verify the setup window/menu, consent, progress, pause/resume, cancellation, accessibility, relaunch, and sandboxed download in the packaged application.
- Verify packaged Metal-resource discovery with inference from the final app/archive; source build success alone does not establish distribution packaging. The build script refuses to package without a metallib and copies SwiftPM resource bundles.
- macOS 14 and memory-poor Apple silicon are not tested; the 36 GB M4 Max measurements cannot qualify 16 GB Macs or final minimum requirements.
- Full 8K context, output exhaustion, sustained/pressure memory, app termination mid-transfer, offline app task planning, adversarial filenames, and complete structured-planning corpus remain downstream/release gates.
- Storage shortage is tested with injected capacity and real files, not by filling the developer's disk. Deliberate process kill and OS resume-temp eviction are not simulated as native GUI actions; invalid resume data and relaunch are covered at the lifecycle/HTTP seams.
