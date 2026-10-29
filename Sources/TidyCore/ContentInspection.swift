import Darwin
import Foundation

// Evidence is intentionally neither Codable nor part of the journal. Future native inspectors
// return this transient value, never excerpts in errors, history, caches or diagnostics.
struct InspectionEvidence: Sendable {
  let kind: String
  let text: String
  let coverage: String
}

public enum InspectionCode: String, Error, Sendable {
  case unsupported, unavailable, changed, inputLimit, taskLimit, modelLimit, unreadable,
    insufficient, deadline

  var explanation: String {
    switch self {
    case .unsupported: "Unsupported or protected contents were not used for naming; left unchanged."
    case .unavailable: "Local contents unavailable; left unchanged."
    case .changed: "File changed since selection; contents not accepted. Left unchanged."
    case .inputLimit: "Content inspection size limit exceeded; left unchanged."
    case .taskLimit: "Aggregate content inspection budget exhausted; left unchanged."
    case .modelLimit: "Evidence exceeds local model limits; left unchanged. Narrow the request."
    case .unreadable: "Contents could not be read in a supported format; left unchanged."
    case .insufficient: "Insufficient readable evidence for a reliable name; left unchanged."
    case .deadline: "Content inspection deadline exceeded; left unchanged."
    }
  }
}

struct InspectionBudget {
  static let fileBytes = 16_384
  var remainingBytes = 65_536
  var remainingPDFBytes = 40 * 1024 * 1024
  var remainingEvidenceBytes = 65_536
  var remainingTime: Duration = .seconds(5)
}

func inspectContents(
  _ item: InventoryItem, root: ScopedDirectory, budget: inout InspectionBudget
) throws -> InspectionEvidence {
  let format = URL(fileURLWithPath: item.name).pathExtension.lowercased()
  if ["pdf", "png", "jpg", "jpeg", "heic", "heif", "tif", "tiff"].contains(format) {
    // Preserve the text aggregate allowance separately from compressed native-document inputs.
    var nativeBudget = InspectionBudget()
    nativeBudget.remainingBytes = budget.remainingPDFBytes
    nativeBudget.remainingTime = budget.remainingTime
    defer {
      budget.remainingPDFBytes = nativeBudget.remainingBytes
      budget.remainingTime = nativeBudget.remainingTime
    }
    let data = try readInspectionInput(
      item, root: root, budget: &nativeBudget, maximumBytes: 20 * 1024 * 1024)
    let evidence = try inspectNativeDocument(data, format: format, budget: &nativeBudget)
    guard evidence.text.utf8.count <= budget.remainingEvidenceBytes else {
      throw InspectionCode.taskLimit
    }
    budget.remainingEvidenceBytes -= evidence.text.utf8.count
    return evidence
  }
  guard ["txt", "md"].contains(format) else {
    throw InspectionCode.unsupported
  }
  var data = try readInspectionInput(
    item, root: root, budget: &budget,
    maximumBytes: InspectionBudget.fileBytes)
  if data.starts(with: [0xEF, 0xBB, 0xBF]) { data.removeFirst(3) }
  guard let text = String(data: data, encoding: .utf8),
    !text.unicodeScalars.contains(where: {
      CharacterSet.controlCharacters.contains($0)
        && !CharacterSet.whitespacesAndNewlines.contains($0)
    })
  else { throw InspectionCode.unreadable }
  guard text.filter(\.isLetter).count >= 8 else { throw InspectionCode.insufficient }
  guard text.utf8.count <= budget.remainingEvidenceBytes else { throw InspectionCode.taskLimit }
  budget.remainingEvidenceBytes -= text.utf8.count
  return InspectionEvidence(kind: "plainText", text: text, coverage: "wholeFile")
}

// Format adapters authorize a supported kind BEFORE this shared snapshot-bound read. PDF/OCR
// adapters must add their own parser containment and output bounds, not bypass this preflight.
func readInspectionInput(
  _ item: InventoryItem, root: ScopedDirectory, budget: inout InspectionBudget, maximumBytes: Int
) throws -> Data {
  guard maximumBytes > 0, maximumBytes < Int.max else { throw InspectionCode.inputLimit }
  try Task.checkCancellation()
  guard budget.remainingTime > .zero, budget.remainingBytes > 0 else {
    throw InspectionCode.taskLimit
  }
  let started = ContinuousClock.now
  defer { budget.remainingTime -= started.duration(to: .now) }
  let deadline = started.advanced(by: min(budget.remainingTime, .seconds(1)))
  guard validSourceAuthority(item.name, item.ancestorIdentities) else {
    throw InspectionCode.changed
  }
  let parent: Int32
  do {
    try validateAncestors(root.fd, item.ancestorIdentities)
    parent = try relativeDirectory(root.fd, relativeParent(item.name))
  } catch { throw InspectionCode.changed }
  defer { close(parent) }
  let leaf = relativeLeaf(item.name)
  let expectedParent =
    relativeParent(item.name) == "."
    ? root.identity : item.ancestorIdentities?[relativeParent(item.name)]
  func recheckAuthority() throws {
    do { try validateAncestors(root.fd, item.ancestorIdentities) } catch {
      throw InspectionCode.changed
    }
    var parentInfo = stat()
    guard fstat(parent, &parentInfo) == 0, FileIdentity(parentInfo) == expectedParent,
      entryInfo(parent, leaf).map(FileSnapshot.init) == item.snapshot,
      entryInfo(root.fd, item.name).map(FileSnapshot.init) == item.snapshot
    else { throw InspectionCode.changed }
  }
  try recheckAuthority()
  guard let before = entryInfo(parent, leaf), before.st_mode & S_IFMT == S_IFREG,
    before.st_nlink == 1, before.st_flags & UInt32(SF_DATALESS) == 0,
    FileSnapshot(before) == item.snapshot
  else { throw InspectionCode.changed }
  // Recheck provider state before opening: a dataless or downloading source must not hydrate.
  let values: URLResourceValues
  do {
    values = try root.url.appendingPathComponent(item.name).resourceValues(forKeys: [
      .isAliasFileKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
      .ubiquitousItemIsDownloadingKey,
    ])
  } catch { throw InspectionCode.unavailable }
  guard values.isAliasFile != true, values.ubiquitousItemIsDownloading != true,
    values.isUbiquitousItem != true
      || values.ubiquitousItemDownloadingStatus == .current
      || values.ubiquitousItemDownloadingStatus == .downloaded
  else { throw InspectionCode.unavailable }
  guard before.st_size <= maximumBytes else { throw InspectionCode.inputLimit }
  guard before.st_size <= budget.remainingBytes else { throw InspectionCode.taskLimit }
  try Task.checkCancellation()
  guard ContinuousClock.now < deadline else { throw InspectionCode.deadline }
  try recheckAuthority()
  let fd = openat(parent, leaf, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
  guard fd >= 0 else { throw InspectionCode.unavailable }
  defer { close(fd) }
  var pinned = stat()
  guard fstat(fd, &pinned) == 0, FileSnapshot(pinned) == item.snapshot,
    pinned.st_mode & S_IFMT == S_IFREG, pinned.st_nlink == 1,
    pinned.st_flags & UInt32(SF_DATALESS) == 0
  else { throw InspectionCode.changed }
  var data = Data()
  var buffer = [UInt8](repeating: 0, count: 4_096)
  while true {
    try Task.checkCancellation()
    guard ContinuousClock.now < deadline else { throw InspectionCode.deadline }
    try recheckAuthority()
    let count = read(
      fd, &buffer,
      min(
        buffer.count,
        maximumBytes + 1 - data.count, budget.remainingBytes + 1))
    guard count >= 0 else { throw InspectionCode.unavailable }
    if count == 0 { break }
    budget.remainingBytes -= count
    guard budget.remainingBytes >= 0 else { throw InspectionCode.taskLimit }
    data.append(contentsOf: buffer.prefix(count))
    guard data.count <= maximumBytes else { throw InspectionCode.inputLimit }
  }
  try Task.checkCancellation()
  guard ContinuousClock.now < deadline else { throw InspectionCode.deadline }
  guard fstat(fd, &pinned) == 0, FileSnapshot(pinned) == item.snapshot,
    entryInfo(root.fd, item.name).map(FileSnapshot.init) == item.snapshot
  else { throw InspectionCode.changed }
  try recheckAuthority()
  return data
}
