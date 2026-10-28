import Darwin
import Foundation
import PDFKit

@_silgen_name("sandbox_init")
private func restrictProcess(
  _ profile: UnsafePointer<CChar>, _ flags: UInt64,
  _ error: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> Int32

struct Reply: Encodable {
  let code: String
  var text = ""
  var coverage = ""
}

func inspect() -> Reply {
  // Independent fail-stop for a parent crash/disconnect while PDFKit is synchronous. Scheduling
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
  guard profile.withCString({ restrictProcess($0, 0, nil) }) == 0 else {
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
  guard input.starts(with: Array("%PDF-".utf8)), let document = PDFDocument(data: input) else {
    return Reply(code: "unreadable")
  }
  guard !document.isEncrypted, !document.isLocked, document.allowsCopying else {
    return Reply(code: "unsupported")
  }
  guard document.pageCount > 0 else { return Reply(code: "insufficient") }
  var text = ""
  let pages = min(document.pageCount, 3)
  for index in 0..<pages {
    guard let page = document.page(at: index) else { return Reply(code: "unreadable") }
    // This rejects excessive evidence rather than accepting a silently truncated title/identifier.
    // PDFKit's own string allocation is NOT bounded by this check; the parent supervises it.
    let value = page.string ?? ""
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
    coverage: document.pageCount > pages ? "first3PagesOnly" : "wholeDocument")
}

if let output = try? JSONEncoder().encode(inspect()), output.count <= 100_000 {
  try? FileHandle.standardOutput.write(contentsOf: output)
}
