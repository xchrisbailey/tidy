# #25 — public OCR cache/temporary-directory contract research

2026-11-03. **No supported end-to-end configuration found; not proof of impossibility.**
Read-only research: Apple documentation, Apple libc source, installed SDK headers.
No probes, tests, apps, mounts, permission changes, dependencies or publications.
The only authored file is this note; production policy remains unchanged.

## Finding

The reviewed public surfaces do not expose a way to bind built-in accurate Vision
OCR's entire compiler/cache/temp activity to one caller-owned bounded directory,
disable every persistent compiler cache, or guarantee memory-only execution.
They also do not specify an exhaustive filesystem/IPC dependency allowlist.
This is a missing documented contract, **not** a claim that accurate OCR cannot
ever work under strict containment. Sources and scope follow below.

The existing [private scratch trial](ticket-25.md#owner-approved-private-scratch-trial)
already failed for accurate revisions 1–3 despite redirected Foundation home/cache
paths and successful scratch-write controls. Its denied Metal application-cache
initialization is a lead, not proof of the sole cause or a sufficient permission.
Neither supplying scratch nor selecting `.accurate` is a demonstrated fix.

## Public controls and their limits

| Surface | Supported contract / consequence |
| --- | --- |
| `VNRecognizeTextRequest` | Recognition level, languages, correction, custom words, minimum text height and revisions; no model URL, compiler options, scratch URL, cache size/location or persistence switch in the reviewed interface. [V1, H] |
| `VNRequest` compute stages | Query devices for the **configured** request, then assign supported devices per stage. Assignments are validated when performing. CPU selection is execution-device control, not a documented prohibition on model loading, compilation, Metal initialization or disk caching. `usesCPUOnly` is deprecated in favor of this API. [V2, H] |
| Background processing | A resource-usage hint that may increase execution time, not a hard memory/disk/time cap or cache switch. [V2, H] |
| `MLModelConfiguration` | Compute units, preferred Metal device, precision, parameters, functions and optimization hints; no reviewed public cache-root, quota or no-persistence option. No public injection of this configuration into built-in text recognition was found. [C1, H] |
| Core ML lifecycle | Apple documents device/configuration-specific specialization during model loading and persistent disk caches, independently of building a `.mlmodelc`. This prevents treating build-time compilation as a general no-runtime-cache guarantee. It does not identify Vision's exact failing internal component. [C2] |
| Metal compiler options | Public `MTLCompileOptions` configures libraries created through caller-owned `MTLDevice.makeLibrary`; no reviewed global cache-root/disable switch or Vision forwarding seam. `enableLogging` enables shader logging, not cache suppression. [M1] |
| Metal binary archives | Caller can load/serialize an explicit archive URL; a nil descriptor URL creates an empty archive. Headers explicitly say archives **augment a separate Metal-maintained app cache**; OS/driver updates can force on-demand compilation. Not a replacement or routing control for Vision's cache. [M2, H] |
| Metal 4 | Reviewed `MTL4CompilerDescriptor` exposes a label and pipeline-data serializer, not an OCR/global cache-routing contract. [M3] |

Apple states Vision APIs run entirely on-device. That supports offline inference,
but is not an exhaustive no-network/no-personal-file/no-other-write security
contract: retain the existing deny rules and negative controls. [V3]

## Foundation paths versus Darwin paths

- `NSTemporaryDirectory()` returns the current user's temporary directory; its
  documented interface has no setter. Finding/creating a temporary directory for
  **our own** files does not redirect another framework's internal files. [F1]
- Apple's `confstr(3)` documents `_CS_DARWIN_USER_TEMP_DIR` and
  `_CS_DARWIN_USER_CACHE_DIR` as query names, not environment variables. These
  queries may create directories. The API has no set operation. [F2]
- In the reviewed Apple libc source, temp lookup asks dirhelper first and consults
  `TMPDIR` only **if that fails**, additionally checking writability. Cache lookup
  asks dirhelper without an equivalent environment fallback. Setting an environment
  variable named `DARWIN_USER_CACHE_DIR` therefore is not a documented override of
  that query. This source is explanatory, not a guarantee about the installed OS's
  complete implementation. [F3]
- Thus the trial's redirected home/`.cachesDirectory` but unchanged temporary path
  is consistent with distinct resolution mechanisms. It does not establish the
  actual Metal path from a reported path length. No supported process-private
  replacement for those Darwin paths was found. Do not force lookup failure,
  redirect shared directories, interpose symbols or grant shared-cache access.

## Precompilation, warmup and memory-only options

- `MLModel.compileModel(at:)` compiles a caller-supplied model to a temporary
  filesystem location and returns its URL; it does not accept an output/temp-root
  argument. Bundling a compiled caller-owned model is supported, but Core ML can
  still specialize it at load time. Neither API exposes Apple's built-in OCR
  model for supported extraction/repackaging/precompilation. [C2, C3, H]
- No public prepare/warmup-only contract for `VNRecognizeTextRequest` was found.
  Running a trusted synthetic image is an ordinary request, not documented proof
  that future revisions, shapes, languages or OS updates avoid compilation/I/O.
  Core ML's advice to keep a caller-owned model loaded does not guarantee Vision
  request/model lifetime or availability across fresh helper processes. [V1, C2]
- In-memory image inputs are public. `MLModelAsset` also supports an in-memory
  specification and, on macOS 15+, in-memory blob mappings for caller-owned
  ML Programs. These are **input/model-storage** APIs, not a promise that internal
  compilation and caches remain in memory; no equivalent built-in OCR model
  substitution seam was found. [V4, H]
- A RAM-backed directory would still require internal cache-path routing; memory
  buffers alone are not a filesystem directory. No reviewed Vision API accepts an
  allocator, directory descriptor, memory filesystem or scratch quota. Changing
  scratch backing therefore does not answer the failed trial's routing question.

Warmup must not parse untrusted bytes before containment. Any future approved
experiment must separately account for startup/warmup and processing, and must
not silently exclude warmup from or extend the production three-second budget.
Public APIs reviewed here provide no hard completion-time guarantee. [V2, C2]

## Other public native text APIs

- Swift `RecognizeTextRequest` (macOS 15+) provides recognition settings and
  in-memory inputs; no documented independent bounded backend/cache control. [V4]
- `RecognizeDocumentsRequest` (macOS 26+) adds document structure, tables and lists;
  its published configuration does not establish an independent OCR engine or
  bounded scratch-only execution. Do not assume either shared or different
  internals without evidence. [V3, V5]
- VisionKit `ImageAnalyzer` (macOS 13+) provides Live Text analysis/configuration,
  but the reviewed public interface does not establish backend independence,
  compiler/cache routing or resource ceilings. It is not a qualified fallback. [V6]
- `VNDetectTextRectanglesRequest` returns text-region/character bounding boxes,
  not recognized strings, so it is not a standalone replacement recognizer. [V7]

## Smallest honest next decision

**Recommend owner-approved Apple technical-support inquiry first**, using the
existing synthetic reproducer and retained logs, not another broader cache grant.
Ask for a documented per-process/per-request cache/temp destination or no-persistent-
cache mode for accurate CPU Vision OCR, its required runtime read/IPC dependencies,
and whether preparation can occur entirely after containment within a fixed budget.
Nothing was submitted by this research task.

If further diagnostics are approved, the smallest useful addition is recording
both Darwin `confstr` paths alongside Foundation paths **inside the same contained
helper**, without granting them access; this only tests the routing hypothesis and
may itself attempt directory creation. It cannot establish a fix. An alternative
request could be tested with identical denials and the three-second budget, but
would remain empirical qualification, not a documented independent backend.
If Apple cannot supply a contract, owner must choose continued safe abstention
versus separately reviewing an alternative OCR dependency/model and its bounds;
no new dependency or relaxation is recommended as already approved.

## Primary sources / inspected headers

- [V1] [VNRecognizeTextRequest](https://developer.apple.com/documentation/vision/vnrecognizetextrequest).
- [V2] [VNRequest](https://developer.apple.com/documentation/vision/vnrequest).
- [V3] [Apple WWDC25: Read documents using Vision](https://developer.apple.com/videos/play/wwdc2025/272/) (introduction and document-reading section).
- [V4] [RecognizeTextRequest](https://developer.apple.com/documentation/vision/recognizetextrequest).
- [V5] [RecognizeDocumentsRequest](https://developer.apple.com/documentation/vision/recognizedocumentsrequest).
- [V6] [ImageAnalyzer](https://developer.apple.com/documentation/visionkit/imageanalyzer).
- [V7] [VNDetectTextRectanglesRequest](https://developer.apple.com/documentation/vision/vndetecttextrectanglesrequest).
- [F1] [NSTemporaryDirectory](https://developer.apple.com/documentation/foundation/nstemporarydirectory()).
- [F2] [Apple libc confstr manual](https://github.com/apple-oss-distributions/Libc/blob/71bbe350ab79eef58113991d817ccc6165061a64/gen/confstr.3).
- [F3] [Apple libc confstr implementation](https://github.com/apple-oss-distributions/Libc/blob/71bbe350ab79eef58113991d817ccc6165061a64/gen/confstr.c).
- [C1] [MLModelConfiguration](https://developer.apple.com/documentation/coreml/mlmodelconfiguration).
- [C2] [Apple WWDC23: Improve Core ML integration](https://developer.apple.com/videos/play/wwdc2023/10049/) (model lifecycle: specialization, disk caching, invalidation and load advice).
- [C3] [Compiling a model on-device](https://developer.apple.com/documentation/coreml/downloading-and-compiling-a-model-on-the-user-s-device).
- [M1] [MTLCompileOptions](https://developer.apple.com/documentation/metal/mtlcompileoptions).
- [M2] [Archive URL](https://developer.apple.com/documentation/metal/mtlbinaryarchivedescriptor/url); separate-cache contract in header below.
- [M3] [MTL4CompilerDescriptor](https://developer.apple.com/documentation/metal/mtl4compilerdescriptor).
- [H] Installed SDK reports **macOS 27.0** in `SDKSettings.json`; no installed-OS version inferred. Headers under `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/`, each `FRAMEWORK.framework/Versions/A/Headers/`: Vision `VNRecognizeTextRequest.h:14–106`, `VNRequest.h:55–64,118–144`; CoreML `MLModelConfiguration.h:17–94`, `MLModel+MLModelCompilation.h:19–58`, `MLModelAsset.h:11–63`; Metal `MTLBinaryArchive.h:35–58`. Header searches found no OCR/Core ML cache-directory/preparation control; this is not an exhaustive proof about every present or future Apple API.
