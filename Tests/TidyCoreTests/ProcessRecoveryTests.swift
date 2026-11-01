import Darwin
import Foundation
import Testing
import TidyCore

struct ProcessRecoveryTests {
  @Test(arguments: [
    "intentSaved", "folderCreated", "beforeMove", "afterMove", "completionSaved",
    "undoIntentSaved", "afterUndoMove", "undoCompletionSaved",
  ])
  func killedProcessReconcilesWithoutResuming(checkpoint: String) async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "tidy-process-recovery-\(UUID())", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("Selected")
    let bookmark = root.appendingPathComponent("settings/folder.bookmark")
    let source = folder.appendingPathComponent("notes.txt")
    let destination = folder.appendingPathComponent("Documents/notes.txt")
    let undo =
      checkpoint == "undoIntentSaved" || checkpoint == "afterUndoMove"
      || checkpoint == "undoCompletionSaved"
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let contents = Data("original bytes\n".utf8)
    try contents.write(to: source)
    let unrelated = folder.appendingPathComponent(".unrelated")
    try Data("untouched".utf8).write(to: unrelated)
    let later = folder.appendingPathComponent("z.txt")
    if !undo { try Data("later".utf8).write(to: later) }

    let process = Process()
    process.executableURL = try workerExecutable()
    process.arguments = [root.path, checkpoint]
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationReason == .uncaughtSignal)
    try #require(process.terminationStatus == SIGKILL)
    #expect(kill(process.processIdentifier, 0) == -1 && errno == ESRCH)

    let journal = bookmark.deletingLastPathComponent().appendingPathComponent("operations.json")
    let persisted = try JSONDecoder().decode([FileOperation].self, from: Data(contentsOf: journal))
    #expect(persisted.count == 1)
    let state: OperationState =
      switch checkpoint {
      case "completionSaved": .completed
      case "undoIntentSaved", "afterUndoMove": .undoIntent
      case "undoCompletionSaved": .undone
      default: .intent
      }
    #expect(persisted.first?.state == state)
    let moved =
      checkpoint == "afterMove" || checkpoint == "completionSaved"
      || checkpoint == "undoIntentSaved"
    #expect(FileManager.default.fileExists(atPath: source.path) == !moved)
    #expect(try Data(contentsOf: moved ? destination : source) == contents)
    let expected: RecoveryStatus =
      switch checkpoint {
      case "folderCreated": .uncertain
      case "afterMove", "completionSaved", "undoIntentSaved": .completed
      case "afterUndoMove", "undoCompletionSaved": .undone
      default: .unapplied
      }
    let recovery = Process()
    recovery.executableURL = try workerExecutable()
    recovery.arguments = [root.path, "recover"]
    let output = Pipe()
    recovery.standardOutput = output
    try recovery.run()
    recovery.waitUntilExit()
    try #require(recovery.terminationReason == .exit && recovery.terminationStatus == 0)
    let statuses = try JSONDecoder().decode(
      [String].self, from: output.fileHandleForReading.readDataToEndOfFile())
    #expect(statuses == [expected.rawValue])

    let reopened = TaskCoordinator(bookmarkFile: bookmark)
    // CLI test executables have different signing identities. The fresh same-helper
    // process above checks restoration; this parent separately regrants its own access.
    _ = try await reopened.selectFolderForWriting(folder)
    let durable = try #require(try await reopened.historySnapshot().operations.first)
    let report = try await reopened.recoveryReport()
    #expect(report.count == 1)
    #expect(report.first?.status == expected)
    let reconciled = try Data(contentsOf: journal)
    #expect(try await reopened.recoveryReport().first?.status == expected)
    #expect(try Data(contentsOf: journal) == reconciled)
    #expect(FileManager.default.fileExists(atPath: source.path) == !moved)
    #expect(try Data(contentsOf: moved ? destination : source) == contents)
    #expect(try Data(contentsOf: unrelated) == Data("untouched".utf8))
    let createdFolder = destination.deletingLastPathComponent()
    #expect(
      FileManager.default.fileExists(atPath: createdFolder.path) == (checkpoint != "intentSaved"))
    if !undo {
      #expect(try Data(contentsOf: later) == Data("later".utf8))
      #expect(
        !FileManager.default.fileExists(
          atPath: folder.appendingPathComponent("Documents/z.txt").path))
    }
    if moved {
      // Recovery must release the killed process's lock and preserve later content edits on undo.
      let handle = try FileHandle(forWritingTo: destination)
      try handle.truncate(atOffset: 0)
      try handle.write(contentsOf: Data("edited later".utf8))
      try handle.close()
      try await reopened.undoTask(durable.taskID)
      #expect(try Data(contentsOf: source) == Data("edited later".utf8))
      #expect(!FileManager.default.fileExists(atPath: destination.deletingLastPathComponent().path))
    } else if checkpoint == "beforeMove" || checkpoint == "afterUndoMove"
      || checkpoint == "undoCompletionSaved"
    {
      #expect(report.first?.options.contains(.cleanupFolders) == true)
      let added = createdFolder.appendingPathComponent("added-later.txt")
      try Data("not task data".utf8).write(to: added)
      try await reopened.undoTask(durable.taskID)
      #expect(try Data(contentsOf: added) == Data("not task data".utf8))
      try FileManager.default.removeItem(at: added)
      try await reopened.undoTask(durable.taskID)
      #expect(!FileManager.default.fileExists(atPath: createdFolder.path))
      #expect(try Data(contentsOf: source) == contents)
    }
  }

  private func workerExecutable() throws -> URL {
    if let path = ProcessInfo.processInfo.environment["TIDY_RECOVERY_TEST_WORKER"] {
      return URL(fileURLWithPath: path)
    }
    let arguments = ProcessInfo.processInfo.arguments
    let index = try #require(arguments.firstIndex(of: "--test-bundle-path"))
    return URL(fileURLWithPath: arguments[index + 1])
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("TidyRecoveryTestWorker")
  }
}
