import CoreImage
import CoreML
import Darwin
import Foundation
import ImageIO
import PDFKit
import Vision

@_silgen_name("sandbox_init")
private func restrictProcess(
  _ profile: UnsafePointer<CChar>, _ flags: UInt64,
  _ error: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> Int32

struct Reply: Encodable {
  let code: String
  var text = ""
  var coverage = ""
  var kind: String?
}

func inspect() -> Reply {
  // Independent fail-stop for a parent crash/disconnect during synchronous native inspection. Scheduling
  // can delay this watchdog; it is not a proof of a hard elapsed-time or unified-memory bound.
  DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3) { _exit(124) }
  // Restrict before parsing any untrusted input. No source paths, writes, network, or core dumps.
  var core = rlimit(rlim_cur: 0, rlim_max: 0)
  guard setrlimit(RLIMIT_CORE, &core) == 0 else { return Reply(code: "unavailable") }
  let ownDirectory = Bundle.main.bundleURL.path
    .replacingOccurrences(of: "\\", with: "\\\\")
    .replacingOccurrences(of: "\"", with: "\\\"")
  let profile = """
    (version 1) (allow default) (deny network*) (deny file-write*) (deny file-read*)
    (deny process-fork) (deny process-exec)
    (allow file-read* (subpath "/System") (subpath "/usr/lib"))
    (allow file-read* (subpath "\(ownDirectory)"))
    """
  guard
    CommandLine.arguments.contains("--inherited-containment")
      || profile.withCString({ restrictProcess($0, 0, nil) }) == 0
  else {
    return Reply(code: "unavailable")
  }
  var input = Data()
  do {
    while let chunk = try FileHandle.standardInput.read(upToCount: 4096), !chunk.isEmpty {
      guard input.count + chunk.count <= 20 * 1024 * 1024 else {
        return Reply(code: "inputLimit")
      }
      input.append(chunk)
    }
  } catch { return Reply(code: "unreadable") }
  let format =
    CommandLine.arguments.first(where: { $0.hasPrefix("--format=") })?
    .replacingOccurrences(of: "--format=", with: "") ?? "pdf"
  if format != "pdf" { return inspectImage(input, format: format) }
  guard input.starts(with: Array("%PDF-".utf8)), let document = PDFDocument(data: input) else {
    return Reply(code: "unreadable")
  }
  guard !document.isEncrypted, !document.isLocked, document.allowsCopying else {
    return Reply(code: "unsupported")
  }
  guard document.pageCount > 0 else { return Reply(code: "insufficient") }
  var text = ""
  var usedOCR = false
  let pages = min(document.pageCount, 3)
  for index in 0..<pages {
    guard let page = document.page(at: index) else { return Reply(code: "unreadable") }
    // This rejects excessive evidence rather than accepting a silently truncated title/identifier.
    // PDFKit's own string allocation is NOT bounded by this check; the parent supervises it.
    var value = page.string ?? ""
    if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      let result: Reply = autoreleasepool {
        guard let image = render(page) else { return Reply(code: "inputLimit") }
        return recognize(image, coverage: "", allowEmpty: true)
      }
      guard result.code == "ok" else { return result }
      value = result.text
      usedOCR = true
    }
    guard value.utf8.count + text.utf8.count + 1 <= 16_384 else {
      return Reply(code: "inputLimit")
    }
    text += value + "\n"
  }
  guard text.filter(\.isLetter).count >= 8,
    !text.unicodeScalars.contains(where: {
      CharacterSet.controlCharacters.contains($0)
        && !CharacterSet.whitespacesAndNewlines.contains($0)
    })
  else { return Reply(code: "insufficient") }
  return Reply(
    code: "ok", text: text,
    coverage: document.pageCount > pages ? "first3PagesOnly" : "wholeDocument",
    kind: usedOCR ? "pdfTextAndOCR" : "pdfText")
}

func render(_ page: PDFPage) -> CGImage? {
  guard let native = page.pageRef else { return nil }
  let box = native.getBoxRect(.cropBox)
  guard [box.origin.x, box.origin.y, box.width, box.height].allSatisfy(\.isFinite),
    box.width > 0, box.height > 0, box.width <= 14_400, box.height <= 14_400,
    abs(box.origin.x) <= 14_400, abs(box.origin.y) <= 14_400
  else { return nil }
  let rotation = ((native.rotationAngle % 360) + 360) % 360
  guard [0, 90, 180, 270].contains(rotation) else { return nil }
  let rotated = rotation == 90 || rotation == 270
  let scale = min(2, 2048 / max(box.width, box.height))
  let width = max(1, Int(ceil((rotated ? box.height : box.width) * scale)))
  let height = max(1, Int(ceil((rotated ? box.width : box.height) * scale)))
  guard width <= 2048, height <= 2048,
    let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8,
      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
  else { return nil }
  let rect = CGRect(x: 0, y: 0, width: width, height: height)
  context.setFillColor(CGColor(gray: 1, alpha: 1))
  context.fill(rect)
  context.concatenate(
    native.getDrawingTransform(.cropBox, rect: rect, rotate: 0, preserveAspectRatio: true))
  context.drawPDFPage(native)
  return context.makeImage()
}

func inspectImage(_ input: Data, format: String) -> Reply {
  let types = [
    "png": ["public.png"], "jpg": ["public.jpeg"], "jpeg": ["public.jpeg"],
    "heic": ["public.heic", "public.heif"], "heif": ["public.heic", "public.heif"],
    "tif": ["public.tiff"], "tiff": ["public.tiff"],
  ]
  guard let expected = types[format],
    let source = CGImageSourceCreateWithData(
      input as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
    let type = CGImageSourceGetType(source), expected.contains(type as String)
  else { return Reply(code: "unreadable") }
  guard CGImageSourceGetCount(source) == 1 else { return Reply(code: "unsupported") }
  guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
    let width = properties[kCGImagePropertyPixelWidth] as? Int,
    let height = properties[kCGImagePropertyPixelHeight] as? Int,
    width > 0, height > 0, width <= 16_384, height <= 16_384,
    width * height <= 40_000_000
  else { return Reply(code: "inputLimit") }
  let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
  guard (1...8).contains(orientation) else { return Reply(code: "unreadable") }
  let options: [CFString: Any] = [
    kCGImageSourceCreateThumbnailFromImageAlways: true,
    kCGImageSourceThumbnailMaxPixelSize: 2048, kCGImageSourceCreateThumbnailWithTransform: true,
    kCGImageSourceShouldCache: false,
  ]
  guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
    image.width > 0, image.height > 0, image.width <= 2048, image.height <= 2048
  else { return Reply(code: "unreadable") }
  var result = recognize(image, coverage: "wholeImage")
  result.kind = "imageOCR"
  return result
}

func recognize(_ image: CGImage, coverage: String, allowEmpty: Bool = false) -> Reply {
  let request = VNRecognizeTextRequest()
  request.revision = VNRecognizeTextRequestRevision3
  // Accurate recognition failed E5 compiler/cache initialization under this profile on the
  // qualification OS. Fast recognition works without cache-write grants; unreadable scans abstain.
  request.recognitionLevel = .fast
  request.automaticallyDetectsLanguage = true
  request.usesLanguageCorrection = false
  request.preferBackgroundProcessing = true
  // Choose CPU compute for every exposed Vision stage, rather than enabling cache writes or
  // relying on locale/default compute selection. Core Image receives a non-caching software context.
  do {
    for (stage, devices) in try request.supportedComputeStageDevices {
      guard
        let cpu = devices.first(where: {
          if case .cpu = $0 { return true }
          return false
        })
      else { return Reply(code: "unavailable") }
      request.setComputeDevice(cpu, for: stage)
    }
    let context = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])
    try VNImageRequestHandler(cgImage: image, orientation: .up, options: [.ciContext: context])
      .perform([request])
  } catch { return Reply(code: "unreadable") }
  var text = ""
  for observation in request.results ?? [] {
    guard let candidate = observation.topCandidates(1).first, candidate.confidence >= 0.5 else {
      return Reply(code: "insufficient")
    }
    guard text.utf8.count + candidate.string.utf8.count + 1 <= 16_384 else {
      return Reply(code: "inputLimit")
    }
    text += candidate.string + "\n"
  }
  guard (allowEmpty && text.isEmpty) || text.filter(\.isLetter).count >= 8 else {
    return Reply(code: "insufficient")
  }
  return Reply(code: "ok", text: text, coverage: coverage)
}

if let output = try? JSONEncoder().encode(inspect()), output.count <= 100_000 {
  try? FileHandle.standardOutput.write(contentsOf: output)
}
