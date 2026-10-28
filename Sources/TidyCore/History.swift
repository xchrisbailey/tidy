import Foundation

public struct HistorySnapshot: Sendable {
  public let operations: [FileOperation]
  /// Logical bytes of retained recovery records, excluding grants, models and lock bookkeeping.
  public let recordBytes: Int64
}

public enum HistoryError: Error, LocalizedError, Equatable {
  case confirmationRequired

  public var errorDescription: String? {
    "Confirm that clearing history permanently removes Tidy’s ability to undo these recorded changes. User files and models will not be changed."
  }
}

extension FileOperation {
  public var originalPath: String {
    URL(fileURLWithPath: selectedFolderPath).appendingPathComponent(originalName).path
  }

  public var resultingPath: String {
    URL(fileURLWithPath: selectedFolderPath).appendingPathComponent(destinationFolder)
      .appendingPathComponent(originalName).path
  }
}

extension TaskCoordinator {
  public func clearHistory(confirmingUndoLoss: Bool) throws {
    guard confirmingUndoLoss else { throw HistoryError.confirmationRequired }
    try Task.checkCancellation()
    let journal = try OperationJournal(directory: bookmarkFile.deletingLastPathComponent())
    // Keep the shared lock and atomic durability; never traverse or remove user/model storage.
    try journal.save([])
  }

  public func historySnapshot() throws -> HistorySnapshot {
    let journal = try OperationJournal(directory: bookmarkFile.deletingLastPathComponent())
    // Browsing must not reconcile or clean up user folders. Undo owns those safety checks.
    let operations = try journal.load()
    let bytes =
      FileManager.default.fileExists(atPath: journal.file.path)
      ? Int64(try Data(contentsOf: journal.file).count) : 0
    return HistorySnapshot(operations: operations, recordBytes: bytes)
  }
}
