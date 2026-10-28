import Darwin
import Foundation

extension TaskCoordinator {
  func planHyphenRename() throws -> SortPlan {
    let root = try writableFolder()
    guard selectedRootIdentity == root.identity, let inventory = selectedInventory,
      inventory.folder == root.url
    else { throw SortError.writeGrantRequired }
    guard inventory.candidateFiles.count <= 1_000 else { throw SortError.scopeTooLarge }
    let journal = try OperationJournal(directory: bookmarkFile.deletingLastPathComponent())
    _ = try journal.load()
    var reserved = try directoryNames(root.fd)
    let candidates = inventory.candidateFiles.sorted { $0.name < $1.name }
    func proposed(_ name: String) -> String {
      let url = URL(fileURLWithPath: name)
      let ext = url.pathExtension
      let stem = ext.isEmpty ? name : url.deletingPathExtension().lastPathComponent
      return stem.replacingOccurrences(of: " ", with: "-") + (ext.isEmpty ? "" : ".\(ext)")
    }
    reserved.formUnion(candidates.map { proposed($0.name).lowercased() })
    var allocated: Set<String> = []
    let existing = try directoryNames(root.fd)
    var changes: [PlannedChange] = []
    var unchanged: [FileOutcome] = []
    for item in candidates {
      try Task.checkCancellation()
      var name = proposed(item.name)
      if name == item.name {
        unchanged.append(
          FileOutcome(
            name: item.name, reason: .alreadyOrganized,
            explanation: "Already matches the naming rule; left unchanged."))
        continue
      }
      guard validFileName(item.name), let snapshot = item.snapshot else {
        throw SortError.invalidPlan
      }
      if existing.contains(name.lowercased()) || allocated.contains(name.lowercased()) {
        let url = URL(fileURLWithPath: name)
        let ext = url.pathExtension
        let stem = ext.isEmpty ? name : url.deletingPathExtension().lastPathComponent
        var suffix = 2
        repeat {
          name = "\(stem) (\(suffix))" + (ext.isEmpty ? "" : ".\(ext)")
          suffix += 1
        } while reserved.contains(name.lowercased())
      }
      guard validFileName(name) else { throw SortError.invalidPlan }
      allocated.insert(name.lowercased())
      reserved.insert(name.lowercased())
      changes.append(
        PlannedChange(
          originalName: item.name, destinationFolder: ".",
          destinationName: name, snapshot: snapshot, destinationIdentity: root.identity))
    }
    let skipped = inventory.skippedItems.map {
      FileOutcome(name: $0.name, reason: .ineligible, explanation: $0.skipReason!.rawValue)
    }
    return SortPlan(
      id: UUID(), changes: changes, unchanged: unchanged, skipped: skipped,
      rootIdentity: root.identity, folder: root.url)
  }
}
