import Darwin
import Foundation

extension TaskCoordinator {
  func expandMetadataPlan(
    _ intent: MetadataIntent, inventory: FolderInventory,
    contentNames: [String: ContentName] = [:]
  ) throws -> SortPlan {
    let root = try writableFolder()
    guard selectedRootIdentity == root.identity, inventory.folder == root.url else {
      throw SortError.writeGrantRequired
    }
    let journal = try OperationJournal(directory: bookmarkFile.deletingLastPathComponent())
    _ = try journal.load()
    let candidates = inventory.candidateFiles.sorted { $0.name < $1.name }
    let decisions = Dictionary(
      uniqueKeysWithValues: intent.files.map { ($0.sourceID, $0.disposition) })
    var proposals: [(InventoryItem, String, String)] = []
    var unchanged: [FileOutcome] = []
    var abstained: [FileOutcome] = []
    for (index, item) in candidates.enumerated() {
      try Task.checkCancellation()
      let ext = URL(fileURLWithPath: item.name).pathExtension
      let selected =
        (intent.selection.extensions.isEmpty
          || intent.selection.extensions.contains { $0.lowercased() == ext.lowercased() })
        && (intent.selection.nameContains.isEmpty
          || relativeLeaf(item.name).contains(intent.selection.nameContains))
      if !selected {
        unchanged.append(
          FileOutcome(
            name: item.name, reason: .outsideRequest,
            explanation: "Outside the requested metadata selection; left unchanged."))
        continue
      }
      guard decisions["f\(index)"] == "apply",
        let folder = metadataFolder(intent.sort, item: item),
        let name = intent.rename.contains(where: { $0.kind == "content" })
          ? contentNames["f\(index)"]?.name : metadataName(intent.rename, item: item)
      else {
        abstained.append(
          FileOutcome(
            name: item.name, reason: .abstained,
            explanation:
              contentNames["f\(index)"]?.explanation
              ?? "Insufficient or ambiguous metadata, or the model abstained. Left untouched."))
        continue
      }
      guard validDestinationFolder(folder) || folder == relativeParent(item.name),
        validFileName(name), !name.hasPrefix("."),
        validNameFragment(name),
        URL(fileURLWithPath: name).pathExtension == ext
      else { throw PlanningError.invalidResponse }
      if folder == relativeParent(item.name), name == relativeLeaf(item.name) {
        unchanged.append(
          FileOutcome(
            name: item.name, reason: .alreadyOrganized,
            explanation: "Already matches the requested rules; left unchanged."))
      } else {
        proposals.append((item, folder, name))
      }
    }
    var identities: [String: FileIdentity] = [:]
    var existing: [String: Set<String>] = [:]
    var reserved: [String: Set<String>] = [:]
    for (_, folder, name) in proposals {
      reserved[folder, default: []].insert(name.lowercased())
      if existing[folder] == nil {
        let info = try checkedEntryInfo(root.fd, folder)
        if let info {
          guard info.st_mode & S_IFMT == S_IFDIR, info.st_flags & UInt32(SF_DATALESS) == 0 else {
            throw SortError.conflict
          }
          if folder != "." {
            let values = try root.url.appendingPathComponent(folder).resourceValues(forKeys: [
              .isPackageKey, .isAliasFileKey,
            ])
            guard values.isPackage != true, values.isAliasFile != true else {
              throw SortError.conflict
            }
          }
          let directory = try childDirectory(root.fd, folder)
          defer { close(directory) }
          var pinned = stat()
          guard fstat(directory, &pinned) == 0, FileIdentity(pinned) == FileIdentity(info) else {
            throw SortError.conflict
          }
          identities[folder] = FileIdentity(info)
          existing[folder] = try directoryNames(directory)
        } else {
          existing[folder] = []
        }
      }
    }
    var changes: [PlannedChange] = []
    var allocated: [String: Set<String>] = [:]
    for (item, folder, proposed) in proposals {
      var name = proposed
      if existing[folder, default: []].contains(name.lowercased())
        || allocated[folder, default: []].contains(name.lowercased())
      {
        let url = URL(fileURLWithPath: proposed)
        let ext = url.pathExtension
        let stem = ext.isEmpty ? proposed : url.deletingPathExtension().lastPathComponent
        var suffix = 2
        repeat {
          name = "\(stem) (\(suffix))" + (ext.isEmpty ? "" : ".\(ext)")
          suffix += 1
        } while existing[folder, default: []].contains(name.lowercased())
          || reserved[folder, default: []].contains(name.lowercased())
      }
      guard validFileName(name), let snapshot = item.snapshot else {
        throw PlanningError.invalidResponse
      }
      allocated[folder, default: []].insert(name.lowercased())
      reserved[folder, default: []].insert(name.lowercased())
      changes.append(
        PlannedChange(
          originalName: item.name, destinationFolder: folder, destinationName: name,
          snapshot: snapshot, destinationIdentity: identities[folder],
          ancestorIdentities: item.ancestorIdentities))
    }
    var plan = SortPlan(
      id: UUID(), changes: changes, unchanged: unchanged,
      skipped: inventory.skippedItems.map {
        FileOutcome(name: $0.name, reason: .ineligible, explanation: $0.skipReason!.rawValue)
      },
      rootIdentity: root.identity, folder: root.url)
    plan.abstained = abstained
    return plan
  }

  private func metadataFolder(_ rule: MetadataIntent.SortRule, item: InventoryItem) -> String? {
    switch rule.kind {
    case "none": return relativeParent(item.name)
    case "type": return destinationFolder(for: item.name)
    case "folder": return rule.value
    case "filenameYear": return filenameDate(relativeLeaf(item.name), precision: .year)
    case "filenameMonth": return filenameDate(relativeLeaf(item.name), precision: .month)
    case "modifiedYear": return item.modificationDate.map { metadataDate($0, precision: .year) }
    case "modifiedMonth": return item.modificationDate.map { metadataDate($0, precision: .month) }
    default: return nil
    }
  }
}

private func metadataName(_ rules: [MetadataIntent.RenameRule], item: InventoryItem) -> String? {
  let url = URL(fileURLWithPath: item.name)
  let ext = url.pathExtension
  var stem = ext.isEmpty ? relativeLeaf(item.name) : url.deletingPathExtension().lastPathComponent
  for rule in rules {
    switch rule.kind {
    case "prefix": stem = stem.hasPrefix(rule.value) ? stem : rule.value + stem
    case "suffix": stem = stem.hasSuffix(rule.value) ? stem : stem + rule.value
    case "filenameDatePrefix", "modifiedDatePrefix":
      let date =
        rule.kind == "filenameDatePrefix"
        ? filenameDate(relativeLeaf(item.name), precision: .day)
        : item.modificationDate.map { metadataDate($0, precision: .day) }
      guard let date else { return nil }
      if !stem.hasPrefix(date) { stem = date + " " + stem }
    default:
      // Dates and digit-bearing identifiers remain byte-for-byte intact even during case/separator changes.
      stem = preservingMetadataTokens(stem) { text in
        switch rule.kind {
        case "separator": text.replacingOccurrences(of: rule.from, with: rule.value)
        case "lowercase": text.lowercased(with: Locale(identifier: "en_US_POSIX"))
        case "uppercase": text.uppercased(with: Locale(identifier: "en_US_POSIX"))
        case "titlecase": text.capitalized(with: Locale(identifier: "en_US_POSIX"))
        default: text
        }
      }
    }
  }
  return stem + (ext.isEmpty ? "" : ".\(ext)")
}

private func preservingMetadataTokens(_ text: String, transform: (String) -> String) -> String {
  let pattern =
    #"(?<![\p{L}\p{M}\p{N}])(?:[A-Fa-f0-9]{8}(?:-[A-Fa-f0-9]{4}){3}-[A-Fa-f0-9]{12}|\d{2}[._-]\d{2}[._-]\d{4}|\d{4}[._-]\d{2}(?:[._-]\d{2})?|[\p{L}\p{M}]+[._-]\p{N}[\p{L}\p{M}\p{N}._-]*|[\p{L}\p{M}\p{N}]*\p{N}[\p{L}\p{M}\p{N}]*)(?![\p{L}\p{M}\p{N}])"#
  guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
  var result = ""
  var start = text.startIndex
  for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
    guard let range = Range(match.range, in: text) else { continue }
    result += transform(String(text[start..<range.lowerBound])) + text[range]
    start = range.upperBound
  }
  return result + transform(String(text[start...]))
}

enum MetadataDatePrecision { case year, month, day }

func metadataDate(_ date: Date, precision: MetadataDatePrecision) -> String {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(secondsFromGMT: 0)!
  let parts = calendar.dateComponents([.year, .month, .day], from: date)
  let year = String(format: "%04d", parts.year!)
  if precision == .year { return year }
  let month = year + String(format: "-%02d", parts.month!)
  return precision == .month ? month : month + String(format: "-%02d", parts.day!)
}

func filenameDate(_ name: String, precision: MetadataDatePrecision) -> String? {
  let pattern =
    #"(?<![\p{L}\p{M}\p{N}])((?:19|20|21)\d{2})(?:[-_]?([0-9]{2})(?:[-_]?([0-9]{2}))?)?(?![\p{L}\p{M}\p{N}])"#
  guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
  var dates: Set<String> = []
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(secondsFromGMT: 0)!
  for match in regex.matches(in: name, range: NSRange(name.startIndex..., in: name)) {
    func part(_ index: Int) -> Int? {
      Range(match.range(at: index), in: name).flatMap { Int(name[$0]) }
    }
    guard let year = part(1), precision == .year || part(2) != nil,
      precision != .day || part(3) != nil
    else { return nil }
    let month = part(2) ?? 1
    let day = part(3) ?? 1
    let components = DateComponents(year: year, month: month, day: day)
    guard let date = calendar.date(from: components),
      calendar.dateComponents([.year, .month, .day], from: date) == components
    else { return nil }
    dates.insert(metadataDate(date, precision: precision))
  }
  return dates.count == 1 ? dates.first : nil
}
