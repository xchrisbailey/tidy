import Darwin
import Foundation

public struct UndoProgress: Sendable {
  public let taskID: UUID
  public let processed: Int
  public let total: Int
  public let undone: Int
}

private struct WriteGrant: Codable {
  let bookmark: Data
  let identity: FileIdentity
}

extension TaskCoordinator {
  private var writeGrantFile: URL { bookmarkFile.appendingPathExtension("write-grant") }

  public func selectFolderForWriting(_ folder: URL) throws -> FolderInventory {
    let inventory = try selectFolder(folder)
    let scoped = try ScopedDirectory(folder)
    let bookmark = try folder.bookmarkData(
      options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    try OperationJournal.persist(
      try JSONEncoder().encode(WriteGrant(bookmark: bookmark, identity: scoped.identity)),
      to: writeGrantFile)
    return inventory
  }

  func writableFolder() throws -> ScopedDirectory {
    do {
      let grant = try JSONDecoder().decode(WriteGrant.self, from: Data(contentsOf: writeGrantFile))
      var stale = false
      let url = try URL(
        resolvingBookmarkData: grant.bookmark,
        options: [.withSecurityScope, .withoutUI, .withoutMounting],
        relativeTo: nil, bookmarkDataIsStale: &stale)
      guard !stale else { throw SortError.writeGrantRequired }
      let scoped = try ScopedDirectory(url)
      guard scoped.identity == grant.identity else { throw SortError.writeGrantRequired }
      return scoped
    } catch { throw SortError.writeGrantRequired }
  }

  public func sortByType(request: String) throws -> FileOperation {
    guard !activeTask else { throw SortError.busy }
    try Task.checkCancellation()
    guard request.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "sort by type"
    else { throw SortError.unsupportedRequest }
    let root = try writableFolder()
    guard selectedRootIdentity == root.identity else { throw SortError.writeGrantRequired }
    guard let inventory = selectedInventory, inventory.folder == root.url,
      inventory.candidateFiles.count == 1, let item = inventory.candidateFiles.first,
      let destination = destinationFolder(for: item.name)
    else { throw SortError.oneFileRequired }
    guard let source = entryInfo(root.fd, item.name), source.st_mode & S_IFMT == S_IFREG,
      source.st_nlink == 1, FileSnapshot(source) == item.snapshot
    else { throw SortError.staleSource }
    let journal = try OperationJournal(directory: bookmarkFile.deletingLastPathComponent())
    var entries = try journal.load()
    let existingDestination = try checkedEntryInfo(root.fd, destination)
    if let existing = existingDestination {
      guard existing.st_mode & S_IFMT == S_IFDIR else { throw SortError.conflict }
      let directory = try childDirectory(root.fd, destination)
      defer { close(directory) }
      guard try checkedEntryInfo(directory, item.name) == nil else { throw SortError.conflict }
    }
    let change = PlannedChange(
      originalName: item.name, destinationFolder: destination, destinationName: item.name,
      snapshot: FileSnapshot(source),
      destinationIdentity: existingDestination.map(FileIdentity.init))
    var createdFolders: [String: FileIdentity] = [:]
    let entry = try apply(
      change, taskID: nil, root: root, journal: journal,
      entries: &entries, createdFolders: &createdFolders)
    selectedInventory = nil
    return entry
  }

  public func undoHistory() throws -> [FileOperation] {
    do { return try loadUndoHistory() } catch {
      recordDiagnostic(.recoveryFailure)
      throw error
    }
  }

  private func loadUndoHistory() throws -> [FileOperation] {
    guard !activeTask else { throw SortError.busy }
    let journal = try OperationJournal(directory: bookmarkFile.deletingLastPathComponent())
    var entries = try journal.load()
    if let root = try? writableFolder() {
      try reconcile(&entries, root: root, journal: journal)
    }
    return entries
  }

  public func undoTask(
    _ taskID: UUID, progress: @Sendable (UndoProgress) async -> Void = { _ in }
  ) async throws {
    do { try await undoRecordedTask(taskID, progress: progress) } catch {
      recordDiagnostic(.recoveryFailure)
      throw error
    }
  }

  private func undoRecordedTask(
    _ taskID: UUID, progress: @Sendable (UndoProgress) async -> Void
  ) async throws {
    guard !activeTask else { throw SortError.busy }
    try Task.checkCancellation()
    let root = try writableFolder()
    let journal = try OperationJournal(directory: bookmarkFile.deletingLastPathComponent())
    var entries = try journal.load()
    try reconcile(&entries, root: root, journal: journal)
    let operations = entries.filter { $0.taskID == taskID }
    guard !operations.isEmpty else { throw SortError.uncertainIdentity }
    activeTask = true
    defer {
      activeTask = false
      selectedInventory = nil
      // Keep cross-coordinator exclusion across every progress suspension, including the last.
      withExtendedLifetime(journal) {}
    }
    await progress(undoProgress(taskID, processed: 0, operations: operations, entries: entries))
    var firstError: (any Error)?
    for (index, entry) in operations.reversed().enumerated() {
      try Task.checkCancellation()
      do {
        try undo(entry.id, root: root, journal: journal, entries: &entries)
      } catch SortError.conflict {
        if firstError == nil { firstError = SortError.conflict }
      } catch SortError.uncertainIdentity {
        if firstError == nil { firstError = SortError.uncertainIdentity }
      } catch SortError.newerOperation {
        if firstError == nil { firstError = SortError.newerOperation }
      } catch {
        // A checkpoint or persistence failure can follow the actual reversal. Report only
        // terminal states retained in the journal, not an optimistic in-memory state.
        let retained = (try? journal.load()) ?? []
        await progress(
          undoProgress(taskID, processed: index + 1, operations: operations, entries: retained))
        throw error
      }
      await progress(
        undoProgress(taskID, processed: index + 1, operations: operations, entries: entries))
    }
    if let firstError { throw firstError }
  }

  private func undoProgress(
    _ taskID: UUID, processed: Int, operations: [FileOperation], entries: [FileOperation]
  ) -> UndoProgress {
    UndoProgress(
      taskID: taskID, processed: processed, total: operations.count,
      undone: entries.filter { $0.taskID == taskID && $0.state == .undone }.count)
  }

  public func undoFile(_ operationID: UUID) throws {
    do { try undoRecordedFile(operationID) } catch {
      recordDiagnostic(.recoveryFailure)
      throw error
    }
  }

  private func undoRecordedFile(_ operationID: UUID) throws {
    guard !activeTask else { throw SortError.busy }
    try Task.checkCancellation()
    let root = try writableFolder()
    let journal = try OperationJournal(directory: bookmarkFile.deletingLastPathComponent())
    var entries = try journal.load()
    try reconcile(&entries, root: root, journal: journal)
    try undo(operationID, root: root, journal: journal, entries: &entries)
  }

  private func undo(
    _ operationID: UUID, root: ScopedDirectory, journal: OperationJournal,
    entries: inout [FileOperation]
  ) throws {
    var rootInfo = stat()
    guard lstat(root.url.path, &rootInfo) == 0, FileIdentity(rootInfo) == root.identity else {
      throw SortError.uncertainIdentity
    }
    guard let index = entries.firstIndex(where: { $0.id == operationID }),
      entries[index].rootIdentity == root.identity
    else { throw SortError.uncertainIdentity }
    var entry = entries[index]
    try validateAncestors(root.fd, entry.ancestorIdentities)
    if entry.state == .undone || entry.state == .notApplied {
      cleanupFolder(entry, root: root)
      return
    }
    guard newerOperation(after: index, in: entries) == nil else { throw SortError.newerOperation }
    guard let folder = try checkedEntryInfo(root.fd, entry.destinationFolder),
      folder.st_mode & S_IFMT == S_IFDIR, FileIdentity(folder) == entry.destinationIdentity
    else { throw SortError.uncertainIdentity }
    let directory = try childDirectory(root.fd, entry.destinationFolder)
    defer { close(directory) }
    var directoryInfo = stat()
    guard
      fstat(directory, &directoryInfo) == 0,
      FileIdentity(directoryInfo) == entry.destinationIdentity,
      entryInfo(root.fd, entry.destinationFolder).map(FileIdentity.init)
        == entry.destinationIdentity
    else { throw SortError.uncertainIdentity }
    guard let file = entryInfo(directory, entry.destinationName),
      FileIdentity(file) == entry.fileIdentity, file.st_mode & S_IFMT == S_IFREG,
      file.st_nlink == 1
    else { throw SortError.uncertainIdentity }
    let sourceFD = try pinFile(directory, entry.destinationName, identity: entry.fileIdentity)
    defer { close(sourceFD) }
    guard
      try destinationAvailable(
        root.fd, entry.originalName,
        caseAliasIdentity: isCaseOnlyRename(
          original: entry.originalName, folder: entry.destinationFolder, name: entry.destinationName
        )
          ? entry.fileIdentity : nil)
    else { throw SortError.conflict }
    entry.state = .undoIntent
    entries[index] = entry
    try journal.save(entries)
    try operationCheckpoint(.undoIntentSaved)
    guard lstat(root.url.path, &rootInfo) == 0, FileIdentity(rootInfo) == root.identity else {
      throw SortError.uncertainIdentity
    }
    try validateAncestors(root.fd, entry.ancestorIdentities)
    guard
      entryInfo(root.fd, entry.destinationFolder).map(FileIdentity.init)
        == entry.destinationIdentity
    else {
      throw SortError.uncertainIdentity
    }
    guard entryInfo(directory, entry.destinationName).map(FileIdentity.init) == entry.fileIdentity
    else { throw SortError.uncertainIdentity }
    try moveExclusive(directory, entry.destinationName, root.fd, as: entry.originalName)
    try operationCheckpoint(.afterUndoMove)
    guard entryInfo(root.fd, entry.originalName).map(FileIdentity.init) == entry.fileIdentity else {
      throw SortError.uncertainIdentity
    }
    entry.state = .undone
    entries[index] = entry
    try journal.save(entries)
    try operationCheckpoint(.undoCompletionSaved)
    for previous in entries
    where previous.rootIdentity == root.identity
      && (previous.state == .undone || previous.state == .notApplied)
    {
      cleanupFolder(previous, root: root)
    }
  }

  private func cleanupFolder(_ entry: FileOperation, root: ScopedDirectory) {
    var rootInfo = stat()
    guard lstat(root.url.path, &rootInfo) == 0, FileIdentity(rootInfo) == root.identity else {
      return
    }
    if let created = entry.createdFolder,
      let current = entryInfo(root.fd, entry.destinationFolder), FileIdentity(current) == created
    {
      // rmdir is atomic and refuses nonempty folders, including files added after the move.
      _ = unlinkat(root.fd, entry.destinationFolder, AT_REMOVEDIR)
      _ = fsync(root.fd)
    }
  }

  func reconcile(
    _ entries: inout [FileOperation], root: ScopedDirectory,
    journal: OperationJournal
  ) throws {
    var changed = false
    for index in entries.indices.reversed() where entries[index].rootIdentity == root.identity {
      let entry = entries[index]
      guard entry.state == .intent || entry.state == .undoIntent else { continue }
      guard newerOperation(after: index, in: entries) == nil else { continue }
      let actual = try? observedOperation(entry, root: root)
      if actual == .completed {
        entries[index].state = .completed
        changed = true
      } else if actual == .notApplied {
        entries[index].state = entry.state == .undoIntent ? .undone : .notApplied
        changed = true
      }
      // Ambiguous interruptions remain intents. Neither a filename nor absence proves identity.
    }
    if changed { try journal.save(entries) }
  }

  func destinationFolder(for name: String) -> String? {
    switch URL(fileURLWithPath: name).pathExtension.lowercased() {
    case "txt", "pdf", "md", "rtf", "doc", "docx", "csv": "Documents"
    case "png", "jpg", "jpeg", "gif", "heic", "tiff": "Images"
    case "mp3", "wav", "m4a", "flac": "Audio"
    case "mp4", "mov", "m4v": "Video"
    case "zip", "tar", "gz", "7z": "Archives"
    default: nil
    }
  }
}
