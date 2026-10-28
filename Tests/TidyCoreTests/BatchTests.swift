import Foundation
import Testing
import TidyCore

struct BatchTests {
  @Test func rejectsUnrepresentableCollisionNamesBeforeCreatingAnyFolders() async throws {
    let fixture = try BatchFixture()
    defer { fixture.remove() }
    let longName = String(repeating: "n", count: 251) + ".txt"
    try fixture.write("a.png")
    try fixture.write(longName)
    try FileManager.default.createDirectory(
      at: fixture.folder.appendingPathComponent("Documents"), withIntermediateDirectories: false)
    try fixture.write("Documents/\(longName)")
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    await #expect(throws: SortError.invalidPlan) {
      try await coordinator.planSortByType(request: "Sort by type")
    }
    #expect(!FileManager.default.fileExists(atPath: fixture.folder.appendingPathComponent("Images").path))
    #expect(try await coordinator.undoHistory().isEmpty)
  }

  @Test func cancellationKeepsCompletedChangesAndExcludesUndoUntilFinished() async throws {
    let fixture = try BatchFixture()
    defer { fixture.remove() }
    for name in ["a.txt", "b.txt", "c.txt"] { try fixture.write(name) }
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    let other = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let plan = try await coordinator.planSortByType(request: "Sort by type")
    let task = Task {
      try await coordinator.execute(plan) { progress in
        if progress.processed == 1 {
          await #expect(throws: SortError.busy) { try await coordinator.undoTask(plan.id) }
          await #expect(throws: SortError.busy) { try await coordinator.undoFile(UUID()) }
          await #expect(throws: SortError.busy) { try await coordinator.execute(plan) }
          await #expect(throws: SortError.busy) { try await other.undoHistory() }
          withUnsafeCurrentTask { $0?.cancel() }
        }
      }
    }
    let result = try await task.value
    #expect(result.cancelled)
    #expect(result.changed.count == 1)
    #expect(result.unprocessed == ["b.txt", "c.txt"])
    #expect(result.isPartial)
    try await other.undoTask(plan.id)
    #expect(try await other.undoHistory().first?.state == .undone)
  }

  @Test func lateDestinationConflictStopsWithoutRollingBackAndCanUndo() async throws {
    let fixture = try BatchFixture()
    defer { fixture.remove() }
    for name in ["a.txt", "b.txt", "c.txt"] { try fixture.write(name) }
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let plan = try await coordinator.planSortByType(request: "Sort by type")
    let result = try await coordinator.execute(plan) { progress in
      if progress.processed == 1 { try? fixture.write("Documents/b.txt") }
    }
    #expect(result.changed.count == 1)
    #expect(result.failed.map(\.name) == ["b.txt"])
    #expect(result.unprocessed == ["c.txt"])
    #expect(result.isPartial)
    #expect(try String(contentsOf: fixture.folder.appendingPathComponent("Documents/b.txt"), encoding: .utf8) == "Documents/b.txt")
    let reopened = TaskCoordinator(bookmarkFile: fixture.bookmark)
    try await reopened.undoTask(plan.id)
    #expect(try String(contentsOf: fixture.folder.appendingPathComponent("a.txt"), encoding: .utf8) == "a.txt")
  }

  @Test(arguments: [100, 101, 1_000, 1_001])
  func countsDistinctChangesAndLimitsEligibleScope(count: Int) async throws {
    let fixture = try BatchFixture()
    defer { fixture.remove() }
    for index in 0..<count { try fixture.write("file-\(index).txt") }
    try fixture.write(".hidden.txt")
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    if count == 1_001 {
      await #expect(throws: SortError.scopeTooLarge) {
        try await coordinator.planSortByType(request: "Sort by type")
      }
    } else {
      let plan = try await coordinator.planSortByType(request: "Sort by type")
      #expect(plan.changedCount == count)
      #expect(plan.moveCount == count)
      #expect(plan.renameCount == 0)
      #expect(plan.requiresConfirmation == (count > 100))
      if count > 100 {
        await #expect(throws: SortError.confirmationRequired) { try await coordinator.execute(plan) }
      } else {
        let result = try await coordinator.execute(plan)
        #expect(result.changed.count == 100)
      }
    }
  }

  @Test func validatesWholePlanBeforeAnyMutation() async throws {
    let fixture = try BatchFixture()
    defer { fixture.remove() }
    try fixture.write("a.txt")
    try fixture.write("z.png")
    try fixture.write("Images")
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    await #expect(throws: SortError.conflict) {
      try await coordinator.planSortByType(request: "Sort by type")
    }
    #expect(!FileManager.default.fileExists(atPath: fixture.folder.appendingPathComponent("Documents").path))
    #expect(try await coordinator.undoHistory().isEmpty)
  }

  @Test func staleAndMissingSourcesAreSkippedAndZeroChangesExplained() async throws {
    let fixture = try BatchFixture()
    defer { fixture.remove() }
    try fixture.write("a.txt")
    try fixture.write("b.txt")
    try fixture.write("unknown.xyz")
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let plan = try await coordinator.planSortByType(request: "Sort by type")
    try FileManager.default.removeItem(at: fixture.folder.appendingPathComponent("a.txt"))
    try Data("replacement".utf8).write(to: fixture.folder.appendingPathComponent("b.txt"))
    let result = try await coordinator.execute(plan)
    #expect(result.changed.isEmpty)
    #expect(result.skipped.filter { $0.reason == .staleSource }.count == 2)
    #expect(result.skipped.filter { $0.reason == .unsupportedType }.count == 1)
    #expect(result.explanation.contains("No files changed"))
    #expect(try await coordinator.undoHistory().isEmpty)
  }

  @Test func reservesCollisionsAndReopensBatchUndo() async throws {
    let fixture = try BatchFixture()
    defer { fixture.remove() }
    try fixture.write("notes.txt")
    try fixture.write("notes (2).txt")
    try FileManager.default.createDirectory(
      at: fixture.folder.appendingPathComponent("Documents"), withIntermediateDirectories: false)
    try fixture.write("Documents/notes.txt")
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let plan = try await coordinator.planSortByType(request: "Sort by type")
    #expect(plan.changedCount == 2)
    #expect(plan.renameCount == 1)
    #expect(plan.moveCount == 2)
    #expect(FileManager.default.fileExists(atPath: fixture.folder.appendingPathComponent("notes.txt").path))
    let result = try await coordinator.execute(plan)
    #expect(result.changed.count == 2)
    #expect(try String(contentsOf: fixture.folder.appendingPathComponent("Documents/notes (3).txt"), encoding: .utf8) == "notes.txt")
    let reopened = TaskCoordinator(bookmarkFile: fixture.bookmark)
    try await reopened.undoTask(plan.id)
    #expect(try String(contentsOf: fixture.folder.appendingPathComponent("notes.txt"), encoding: .utf8) == "notes.txt")
    #expect(try await reopened.undoHistory().filter { $0.state == .undone }.count == 2)
  }
}

private struct BatchFixture {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent("tidy-batch-\(UUID())")
  var folder: URL { root.appendingPathComponent("Selected") }
  var bookmark: URL { root.appendingPathComponent("settings/folder.bookmark") }
  init() throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  }
  func write(_ name: String) throws {
    try Data(name.utf8).write(to: folder.appendingPathComponent(name))
  }
  func remove() { try? FileManager.default.removeItem(at: root) }
}
