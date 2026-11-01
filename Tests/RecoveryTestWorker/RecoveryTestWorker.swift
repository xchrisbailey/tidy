import Darwin
import Foundation
import TidyCore

@main
struct RecoveryTestWorker {
  static func main() async throws {
    let arguments = CommandLine.arguments
    guard arguments.count == 3 || arguments.count == 4 else { exit(2) }
    // A stalled fixture must fail rather than leave the parent waiting indefinitely.
    alarm(20)
    let root = URL(fileURLWithPath: arguments[1], isDirectory: true)
    let bookmark = root.appendingPathComponent("settings/folder.bookmark")
    if arguments[2] == "recover" {
      let coordinator = TaskCoordinator(bookmarkFile: bookmark)
      let statuses = try await coordinator.recoveryReport().map { $0.status.rawValue }
      try FileHandle.standardOutput.write(contentsOf: JSONEncoder().encode(statuses))
      return
    }
    if arguments[2] == "undo" {
      let coordinator = TaskCoordinator(bookmarkFile: bookmark)
      let operations = try await coordinator.undoHistory()
      guard let task = operations.first?.taskID else { exit(2) }
      try await coordinator.undoTask(task)
      return
    }
    let checkpoint: OperationCheckpoint
    switch arguments[2] {
    case "intentSaved": checkpoint = .intentSaved
    case "folderCreated": checkpoint = .folderCreated
    case "beforeMove": checkpoint = .beforeMove
    case "afterMove": checkpoint = .afterMove
    case "completionSaved": checkpoint = .completionSaved
    case "undoIntentSaved": checkpoint = .undoIntentSaved
    case "afterUndoMove": checkpoint = .afterUndoMove
    case "undoCompletionSaved": checkpoint = .undoCompletionSaved
    default: exit(2)
    }
    let coordinator = TaskCoordinator(
      bookmarkFile: bookmark
    ) { point in
      if point == checkpoint {
        // SIGKILL bypasses Swift unwinding, journal deinit and normal task finalization.
        kill(getpid(), SIGKILL)
        while true { pause() }
      }
    }
    let folder =
      arguments.count == 4
      ? URL(fileURLWithPath: arguments[3], isDirectory: true)
      : root.appendingPathComponent("Selected")
    _ = try await coordinator.selectFolderForWriting(folder)
    let plan = try await coordinator.planSortByType(request: "Sort by type")
    _ = try await coordinator.execute(plan)
    if checkpoint == .undoIntentSaved || checkpoint == .afterUndoMove
      || checkpoint == .undoCompletionSaved
    {
      try await coordinator.undoTask(plan.id)
    }
    exit(4)
  }
}
