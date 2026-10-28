import Darwin
import Foundation

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
    let sourceFD = try pinFile(root.fd, item.name, identity: FileIdentity(source))
    defer { close(sourceFD) }
    let journal = try OperationJournal(directory: bookmarkFile.deletingLastPathComponent())
    var entries = try journal.load()
    let existingDestination = try checkedEntryInfo(root.fd, destination)
    if let existing = existingDestination {
      guard existing.st_mode & S_IFMT == S_IFDIR else { throw SortError.conflict }
      let directory = try childDirectory(root.fd, destination)
      defer { close(directory) }
      guard try checkedEntryInfo(directory, item.name) == nil else { throw SortError.conflict }
    }
    var entry = FileOperation(
      id: UUID(), originalName: item.name, destinationFolder: destination,
      selectedFolderPath: root.url.path, state: .intent,
      rootIdentity: root.identity, fileIdentity: FileIdentity(source))
    entries.append(entry)
    try journal.save(entries)
    try operationCheckpoint(.intentSaved)
    if existingDestination == nil {
      guard mkdirat(root.fd, destination, 0o755) == 0,
        let created = entryInfo(root.fd, destination)
      else { throw SortError.conflict }
      try operationCheckpoint(.folderCreated)
      entry.createdFolder = FileIdentity(created)
      entries[entries.count - 1] = entry
      try journal.save(entries)
    }
    let directory = try childDirectory(root.fd, destination)
    defer { close(directory) }
    var directoryInfo = stat()
    guard fstat(directory, &directoryInfo) == 0,
      entryInfo(root.fd, destination).map(FileIdentity.init) == FileIdentity(directoryInfo),
      FileIdentity(directoryInfo)
        == (entry.createdFolder ?? existingDestination.map(FileIdentity.init))
    else { throw SortError.conflict }
    entry.destinationIdentity = FileIdentity(directoryInfo)
    entries[entries.count - 1] = entry
    guard fsync(root.fd) == 0 else { throw SortError.unavailable }
    try journal.save(entries)
    guard let current = entryInfo(root.fd, item.name), FileIdentity(current) == entry.fileIdentity,
      FileSnapshot(current) == item.snapshot
    else { throw SortError.staleSource }
    try operationCheckpoint(.beforeMove)
    try moveExclusive(root.fd, item.name, directory)
    try operationCheckpoint(.afterMove)
    guard entryInfo(directory, item.name).map(FileIdentity.init) == entry.fileIdentity else {
      throw SortError.uncertainIdentity
    }
    entry.state = .completed
    entries[entries.count - 1] = entry
    try journal.save(entries)
    try operationCheckpoint(.completionSaved)
    selectedInventory = nil
    return entry
  }

  public func undoHistory() throws -> [FileOperation] {
    guard !activeTask else { throw SortError.busy }
    let journal = try OperationJournal(directory: bookmarkFile.deletingLastPathComponent())
    var entries = try journal.load()
    if let root = try? writableFolder() {
      try reconcile(&entries, root: root, journal: journal)
    }
    return entries
  }

  public func undoTask(_ taskID: UUID) throws {
    guard !activeTask else { throw SortError.busy }
    try Task.checkCancellation()
    let root = try writableFolder()
    let journal = try OperationJournal(directory: bookmarkFile.deletingLastPathComponent())
    var entries = try journal.load()
    try reconcile(&entries, root: root, journal: journal)
    let operations = entries.filter { $0.taskID == taskID }
    guard !operations.isEmpty else { throw SortError.uncertainIdentity }
    var firstError: (any Error)?
    for entry in operations.reversed() {
      try Task.checkCancellation()
      do {
        try undo(entry.id, root: root, journal: journal, entries: &entries)
      } catch SortError.conflict {
        if firstError == nil { firstError = SortError.conflict }
      } catch SortError.uncertainIdentity {
        if firstError == nil { firstError = SortError.uncertainIdentity }
      } catch SortError.newerOperation {
        if firstError == nil { firstError = SortError.newerOperation }
      }
    }
    if let firstError { throw firstError }
  }

  public func undoFile(_ operationID: UUID) throws {
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
    guard let index = entries.firstIndex(where: { $0.id == operationID }),
      entries[index].rootIdentity == root.identity
    else { throw SortError.uncertainIdentity }
    var entry = entries[index]
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
    guard try checkedEntryInfo(root.fd, entry.originalName) == nil else { throw SortError.conflict }
    entry.state = .undoIntent
    entries[index] = entry
    try journal.save(entries)
    try operationCheckpoint(.undoIntentSaved)
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
