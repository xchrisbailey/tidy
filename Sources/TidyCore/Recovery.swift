import Darwin
import Foundation

/// Synchronous diagnostics at the durable task boundary, including local interruption injection.
/// A thrown error stops the task without rollback; the durable journal remains authoritative on reopen.
public enum OperationCheckpoint: Sendable {
  case intentSaved, folderCreated, beforeMove, afterMove, completionSaved
  case undoIntentSaved, afterUndoMove, undoCompletionSaved
}

public enum RecoveryStatus: String, Sendable {
  case completed, unapplied, undone, uncertain
}

public enum RecoveryOption: String, Sendable {
  case undoFile, undoTask, cleanupFolders, inspect, grantAccess
}

public struct RecoveryOperation: Sendable, Identifiable {
  public var id: UUID { operation.id }
  public let operation: FileOperation
  public let status: RecoveryStatus
  public let blockingTaskID: UUID?
  public let options: [RecoveryOption]
  public let explanation: String
}

extension TaskCoordinator {
  /// Reconcile durable records only. Never resume a move, undo, or folder removal on reopen.
  public func recoveryReport() throws -> [RecoveryOperation] {
    guard !activeTask else { throw SortError.busy }
    let journal = try OperationJournal(directory: bookmarkFile.deletingLastPathComponent())
    var entries = try journal.load()
    let root = try? writableFolder()
    if let root { try reconcile(&entries, root: root, journal: journal) }
    return entries.enumerated().map { index, entry in
      guard let root, entry.rootIdentity == root.identity else {
        return RecoveryOperation(
          operation: entry, status: .uncertain, blockingTaskID: nil,
          options: [.grantAccess, .inspect],
          explanation:
            "Grant access to the recorded original folder to check actual state. No changes were resumed."
        )
      }
      if let newer = newerOperation(after: index, in: entries),
        entry.state != .undone && entry.state != .notApplied
      {
        return RecoveryOperation(
          operation: entry, status: entry.state == .completed ? .completed : .uncertain,
          blockingTaskID: newer.taskID, options: [.inspect],
          explanation:
            "Newer task \(newer.taskID) blocks this file. Undo the newer change first; no other task will be undone automatically."
        )
      }
      let actual = try? observedOperation(entry, root: root)
      let status: RecoveryStatus
      if actual == .completed, entry.state == .completed {
        status = .completed
      } else if actual == .notApplied, entry.state == .undone || entry.state == .notApplied {
        status = entry.state == .undone ? .undone : .unapplied
      } else {
        status = .uncertain
      }
      let occupied = entryInfo(root.fd, entry.originalName) != nil
      let options: [RecoveryOption]
      let explanation: String
      switch status {
      case .completed:
        options = occupied ? [.inspect] : [.undoFile, .undoTask, .inspect]
        explanation =
          occupied
          ? "Completed file identified, but its original location is occupied. Nothing will be overwritten."
          : "Completed file identified. Undo preserves later content edits to this same file."
      case .unapplied, .undone:
        options = entry.createdFolder == nil ? [.inspect] : [.cleanupFolders, .inspect]
        explanation =
          status == .undone
          ? "File restored. Explicit cleanup may remove only identified empty task-created folders."
          : "File remains at its original location; no move will be resumed."
      case .uncertain:
        options = [.inspect]
        explanation =
          "Missing file, changed folder, or uncertain identity. Inspect the recorded paths; no completion was assumed and nothing was resumed."
      }
      return RecoveryOperation(
        operation: entry, status: status, blockingTaskID: nil,
        options: options, explanation: explanation)
    }
  }
}

// Inspect only pinned, no-follow directories and ordinary single-link files. Names alone are not proof.
func observedOperation(_ entry: FileOperation, root: ScopedDirectory) throws -> OperationState? {
  var rootInfo = stat()
  guard lstat(root.url.path, &rootInfo) == 0, FileIdentity(rootInfo) == root.identity else {
    return nil
  }
  let original = try checkedEntryInfo(root.fd, entry.originalName)
  let folder = try checkedEntryInfo(root.fd, entry.destinationFolder)
  var resulting: stat?
  if let folder {
    guard folder.st_mode & S_IFMT == S_IFDIR,
      FileIdentity(folder) == (entry.destinationIdentity ?? entry.createdFolder)
    else { return nil }
    let directory = try childDirectory(root.fd, entry.destinationFolder)
    defer { close(directory) }
    var info = stat()
    guard fstat(directory, &info) == 0, FileIdentity(info) == FileIdentity(folder),
      entryInfo(root.fd, entry.destinationFolder).map(FileIdentity.init) == FileIdentity(folder)
    else { return nil }
    resulting = try checkedEntryInfo(directory, entry.destinationName)
  }
  func matches(_ info: stat?) -> Bool {
    guard let info else { return false }
    return info.st_mode & S_IFMT == S_IFREG && info.st_nlink == 1
      && FileIdentity(info) == entry.fileIdentity
  }
  if matches(resulting), !matches(original) { return .completed }
  if matches(original), resulting == nil { return .notApplied }
  return nil
}

// Journal order, not timestamps or filenames, defines precedence for a file identity.
func newerOperation(after index: Int, in entries: [FileOperation]) -> FileOperation? {
  entries.dropFirst(index + 1).last {
    $0.fileIdentity == entries[index].fileIdentity && $0.state != .undone && $0.state != .notApplied
  }
}
