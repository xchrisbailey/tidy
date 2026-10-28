import Darwin
import Foundation

public struct SortPlan: Sendable, Identifiable {
  public let id: UUID
  public let changes: [PlannedChange]
  public let unchanged: [FileOutcome]
  public let skipped: [FileOutcome]
  public internal(set) var abstained: [FileOutcome] = []
  let rootIdentity: FileIdentity
  let folder: URL
  public var changedCount: Int { changes.count }
  public var renameCount: Int {
    changes.filter { relativeLeaf($0.originalName) != $0.destinationName }.count
  }
  public var moveCount: Int {
    changes.filter { $0.destinationFolder != relativeParent($0.originalName) }.count
  }
  public var requiresConfirmation: Bool { changedCount > 100 }
}

public struct PlannedChange: Sendable {
  public let originalName: String
  public let destinationFolder: String
  public let destinationName: String
  let snapshot: FileSnapshot
  let destinationIdentity: FileIdentity?
  var ancestorIdentities: [String: FileIdentity]? = nil
}

public enum OutcomeReason: String, Sendable {
  case ineligible, unsupportedType, alreadyOrganized, outsideRequest, abstained, staleSource,
    failure
}

public struct FileOutcome: Sendable {
  public let name: String
  public let reason: OutcomeReason
  public let explanation: String
  public internal(set) var inspectionCode: InspectionCode? = nil
}

public struct BatchProgress: Sendable {
  public let taskID: UUID
  public let processed: Int
  public let total: Int
  public let changed: Int
}

public struct BatchResult: Sendable {
  public let taskID: UUID
  public internal(set) var changed: [FileOperation] = []
  public internal(set) var unchanged: [FileOutcome]
  public internal(set) var skipped: [FileOutcome]
  public internal(set) var failed: [FileOutcome] = []
  public internal(set) var abstained: [FileOutcome] = []
  public internal(set) var unprocessed: [String] = []
  public internal(set) var cancelled = false
  public internal(set) var failureExplanation: String?
  public var isPartial: Bool { cancelled || failureExplanation != nil }
  public var explanation: String {
    let counts =
      "\(changed.count) changed · \(unchanged.count) unchanged · \(abstained.count) abstained · \(skipped.count) skipped · \(failed.count) failed · \(unprocessed.count) not processed."
    if cancelled { return "Cancelled. \(counts) Completed changes remain available for undo." }
    if let failureExplanation {
      return
        "Stopped after a failure. \(counts) \(failureExplanation) Check undo history; no automatic rollback was attempted."
    }
    if changed.isEmpty {
      return
        "No files changed. \(counts) See the per-file reasons; existing folders were preserved."
    }
    return "\(counts) Completed changes are available for undo."
  }
}

extension TaskCoordinator {
  public func planSortByType(request: String) throws -> SortPlan {
    guard !activeTask else { throw SortError.busy }
    try Task.checkCancellation()
    guard request.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "sort by type"
    else { throw SortError.unsupportedRequest }
    let root = try writableFolder()
    guard selectedRootIdentity == root.identity, let inventory = selectedInventory,
      inventory.folder == root.url
    else { throw SortError.writeGrantRequired }
    guard inventory.candidateFiles.count <= 1_000 else { throw SortError.scopeTooLarge }
    // Hold the same cross-coordinator lock while inspecting the entire plan. Nothing is mutated.
    let journal = try OperationJournal(directory: bookmarkFile.deletingLastPathComponent())
    _ = try journal.load()
    let candidates = inventory.candidateFiles.sorted { $0.name < $1.name }
    var reserved: [String: Set<String>] = [:]
    for item in candidates {
      if let destination = destinationFolder(for: item.name) {
        reserved[destination, default: []].insert(item.name.lowercased())
      }
    }
    var changes: [PlannedChange] = []
    var allocated: [String: Set<String>] = [:]
    var skipped = inventory.skippedItems.map {
      FileOutcome(name: $0.name, reason: .ineligible, explanation: $0.skipReason!.rawValue)
    }
    for item in candidates {
      try Task.checkCancellation()
      guard let destination = destinationFolder(for: item.name) else {
        skipped.append(
          FileOutcome(
            name: item.name, reason: .unsupportedType,
            explanation: "No supported type rule; the file was left untouched."))
        continue
      }
      guard validFileName(item.name), let snapshot = item.snapshot else {
        throw SortError.invalidPlan
      }
      let folderInfo = try checkedEntryInfo(root.fd, destination)
      var existingNames: Set<String> = []
      if let folderInfo {
        guard folderInfo.st_mode & S_IFMT == S_IFDIR else { throw SortError.conflict }
        let directory = try childDirectory(root.fd, destination)
        defer { close(directory) }
        var info = stat()
        guard fstat(directory, &info) == 0, FileIdentity(info) == FileIdentity(folderInfo) else {
          throw SortError.conflict
        }
        // Metadata-only enumeration also reserves case variants on case-sensitive volumes.
        existingNames = try directoryNames(directory)
      }
      var name = item.name
      if existingNames.contains(name.lowercased())
        || allocated[destination, default: []].contains(name.lowercased())
      {
        let url = URL(fileURLWithPath: item.name)
        let ext = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent
        var suffix = 2
        repeat {
          name = "\(stem) (\(suffix))" + (ext.isEmpty ? "" : ".\(ext)")
          suffix += 1
        } while existingNames.contains(name.lowercased())
          || reserved[destination, default: []].contains(name.lowercased())
      }
      guard validFileName(name) else { throw SortError.invalidPlan }
      reserved[destination, default: []].insert(name.lowercased())
      allocated[destination, default: []].insert(name.lowercased())
      changes.append(
        PlannedChange(
          originalName: item.name, destinationFolder: destination,
          destinationName: name, snapshot: snapshot,
          destinationIdentity: folderInfo.map(FileIdentity.init)))
    }
    return SortPlan(
      id: UUID(), changes: changes, unchanged: [], skipped: skipped,
      rootIdentity: root.identity, folder: root.url)
  }

  public func execute(
    _ plan: SortPlan, confirmed: Bool = false,
    progress: @Sendable (BatchProgress) async -> Void = { _ in }
  ) async throws -> BatchResult {
    guard !activeTask else { throw SortError.busy }
    guard !plan.requiresConfirmation || confirmed else { throw SortError.confirmationRequired }
    let root = try writableFolder()
    guard root.identity == plan.rootIdentity, root.url == plan.folder else {
      throw SortError.invalidPlan
    }
    // Plans are immutable and only created here; still validate every operation before any mutation.
    guard plan.changes.count <= 1_000,
      Set(plan.changes.map(\.originalName)).count == plan.changes.count,
      Set(plan.changes.map { "\($0.destinationFolder)/\($0.destinationName.lowercased())" }).count
        == plan.changes.count,
      plan.changes.allSatisfy({
        validSourceAuthority($0.originalName, $0.ancestorIdentities)
          && validFileName($0.destinationName)
          && (validDestinationFolder($0.destinationFolder)
            || $0.destinationFolder == relativeParent($0.originalName))
      })
    else { throw SortError.invalidPlan }
    let journal = try OperationJournal(directory: bookmarkFile.deletingLastPathComponent())
    var entries = try journal.load()
    guard !entries.contains(where: { $0.taskID == plan.id }) else { throw SortError.invalidPlan }
    // Validate every destination again before the first operation, including after confirmation.
    for change in plan.changes {
      try validateAncestors(root.fd, change.ancestorIdentities)
      let info = try checkedEntryInfo(root.fd, change.destinationFolder)
      guard info.map(FileIdentity.init) == change.destinationIdentity else {
        throw SortError.conflict
      }
      if info != nil {
        let directory = try childDirectory(root.fd, change.destinationFolder)
        defer { close(directory) }
        guard try checkedEntryInfo(directory, change.destinationName) == nil else {
          throw SortError.conflict
        }
      }
    }
    activeTask = true
    defer {
      activeTask = false
      selectedInventory = nil
    }
    var result = BatchResult(taskID: plan.id, unchanged: plan.unchanged, skipped: plan.skipped)
    result.abstained = plan.abstained
    var createdFolders: [String: FileIdentity] = [:]
    for (index, change) in plan.changes.enumerated() {
      await progress(
        BatchProgress(
          taskID: plan.id, processed: index,
          total: plan.changedCount, changed: result.changed.count))
      if Task.isCancelled {
        result.cancelled = true
        result.unprocessed = plan.changes[index...].map(\.originalName)
        break
      }
      guard let source = entryInfo(root.fd, change.originalName),
        source.st_mode & S_IFMT == S_IFREG, source.st_nlink == 1,
        FileSnapshot(source) == change.snapshot
      else {
        result.skipped.append(
          FileOutcome(
            name: change.originalName, reason: .staleSource,
            explanation: SortError.staleSource.localizedDescription))
        continue
      }
      do {
        let entry = try apply(
          change, taskID: plan.id, root: root, journal: journal,
          entries: &entries, createdFolders: &createdFolders)
        result.changed.append(entry)
      } catch SortError.staleSource {
        result.skipped.append(
          FileOutcome(
            name: change.originalName, reason: .staleSource,
            explanation: SortError.staleSource.localizedDescription))
      } catch {
        // The exclusive rename may have succeeded before a flush or final journal save failed.
        // Count the actual change without claiming its durable completion; reopen reconciles intent.
        if let entry = entries.last, entry.taskID == plan.id,
          entry.originalName == change.originalName, movedFileExists(entry, root: root)
        {
          result.changed.append(entry)
          result.failureExplanation =
            "\(change.originalName) moved, but its final recovery record or filesystem flush could not be confirmed. \(error.localizedDescription)"
        } else {
          result.failed.append(
            FileOutcome(
              name: change.originalName, reason: .failure,
              explanation: error.localizedDescription))
          result.failureExplanation = error.localizedDescription
        }
        result.unprocessed = plan.changes.dropFirst(index + 1).map(\.originalName)
        break
      }
    }
    await progress(
      BatchProgress(
        taskID: plan.id,
        processed: plan.changedCount - result.unprocessed.count,
        total: plan.changedCount, changed: result.changed.count))
    // Optimized builds must retain cross-instance exclusion through the final callback too.
    withExtendedLifetime(journal) {}
    return result
  }

  private func apply(
    _ change: PlannedChange, taskID: UUID, root: ScopedDirectory, journal: OperationJournal,
    entries: inout [FileOperation], createdFolders: inout [String: FileIdentity]
  ) throws -> FileOperation {
    var rootInfo = stat()
    guard lstat(root.url.path, &rootInfo) == 0, FileIdentity(rootInfo) == root.identity else {
      throw SortError.uncertainIdentity
    }
    let sourceFD = try pinFile(root.fd, change.originalName, identity: change.snapshot.identity)
    defer { close(sourceFD) }
    let existing = try checkedEntryInfo(root.fd, change.destinationFolder)
    let expected = change.destinationIdentity ?? createdFolders[change.destinationFolder]
    guard existing.map(FileIdentity.init) == expected else { throw SortError.conflict }
    if existing != nil {
      let directory = try childDirectory(root.fd, change.destinationFolder)
      defer { close(directory) }
      guard try checkedEntryInfo(directory, change.destinationName) == nil else {
        throw SortError.conflict
      }
    }
    var entry = FileOperation(
      id: UUID(), originalName: change.originalName,
      destinationFolder: change.destinationFolder, selectedFolderPath: root.url.path,
      batchID: taskID, resultingName: change.destinationName, state: .intent,
      rootIdentity: root.identity, fileIdentity: change.snapshot.identity)
    entry.ancestorIdentities = change.ancestorIdentities
    entries.append(entry)
    let index = entries.count - 1
    try journal.save(entries)
    try operationCheckpoint(.intentSaved)
    if existing == nil {
      guard mkdirat(root.fd, change.destinationFolder, 0o755) == 0,
        let created = entryInfo(root.fd, change.destinationFolder)
      else { throw SortError.conflict }
      try operationCheckpoint(.folderCreated)
      entry.createdFolder = FileIdentity(created)
      createdFolders[change.destinationFolder] = entry.createdFolder
      entries[index] = entry
      try journal.save(entries)
    }
    let directory = try childDirectory(root.fd, change.destinationFolder)
    defer { close(directory) }
    var info = stat()
    guard fstat(directory, &info) == 0,
      FileIdentity(info) == (expected ?? entry.createdFolder),
      entryInfo(root.fd, change.destinationFolder).map(FileIdentity.init) == FileIdentity(info)
    else { throw SortError.conflict }
    entry.destinationIdentity = FileIdentity(info)
    entries[index] = entry
    guard fsync(root.fd) == 0 else { throw SortError.unavailable }
    try journal.save(entries)
    guard let current = entryInfo(root.fd, change.originalName),
      FileSnapshot(current) == change.snapshot
    else {
      entry.state = .notApplied
      entries[index] = entry
      try journal.save(entries)
      throw SortError.staleSource
    }
    try operationCheckpoint(.beforeMove)
    try validateAncestors(root.fd, change.ancestorIdentities)
    let sourceParent = try relativeDirectory(root.fd, relativeParent(change.originalName))
    defer { close(sourceParent) }
    var parentInfo = stat()
    guard fstat(sourceParent, &parentInfo) == 0,
      FileIdentity(parentInfo)
        == (change.ancestorIdentities?[relativeParent(change.originalName)] ?? root.identity),
      entryInfo(root.fd, change.destinationFolder).map(FileIdentity.init)
        == entry.destinationIdentity
    else { throw SortError.uncertainIdentity }
    guard let current = entryInfo(sourceParent, relativeLeaf(change.originalName)),
      FileSnapshot(current) == change.snapshot
    else { throw SortError.staleSource }
    try moveExclusive(
      sourceParent, relativeLeaf(change.originalName), directory, as: change.destinationName)
    try operationCheckpoint(.afterMove)
    guard entryInfo(directory, change.destinationName).map(FileIdentity.init) == entry.fileIdentity
    else { throw SortError.uncertainIdentity }
    entry.state = .completed
    entries[index] = entry
    try journal.save(entries)
    try operationCheckpoint(.completionSaved)
    return entry
  }

  private func movedFileExists(_ entry: FileOperation, root: ScopedDirectory) -> Bool {
    guard entryInfo(root.fd, entry.originalName) == nil,
      entryInfo(root.fd, entry.destinationFolder).map(FileIdentity.init)
        == entry.destinationIdentity,
      let directory = try? childDirectory(root.fd, entry.destinationFolder)
    else { return false }
    defer { close(directory) }
    return entryInfo(directory, entry.destinationName).map(FileIdentity.init) == entry.fileIdentity
  }
}
