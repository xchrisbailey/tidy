import Foundation
import Testing
import TidyCore

struct BatchTests {
  @Test func batchUndoPreservesConflictsAndIndividualUndoKeepsOtherChanges() async throws {
    let fixture = try BatchFixture()
    defer { fixture.remove() }
    for name in ["a.txt", "b.txt", "c.txt"] { try fixture.write(name) }
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let plan = try await coordinator.planSortByType(request: "Sort by type")
    let result = try await coordinator.execute(plan)
    let first = try #require(result.changed.first)
    let reopened = TaskCoordinator(bookmarkFile: fixture.bookmark)
    try await reopened.undoFile(first.id)
    #expect(
      FileManager.default.fileExists(
        atPath: fixture.folder.appendingPathComponent("Documents/b.txt").path))
    try Data("occupied".utf8).write(to: fixture.folder.appendingPathComponent("b.txt"))
    await #expect(throws: SortError.conflict) { try await reopened.undoTask(plan.id) }
    let history = try await reopened.historySnapshot()
    #expect(history.tasks.count == 1)
    #expect(history.operations.filter { $0.state == .undone }.count == 2)
    #expect(
      try String(contentsOf: fixture.folder.appendingPathComponent("b.txt"), encoding: .utf8)
        == "occupied")
    #expect(
      try String(
        contentsOf: fixture.folder.appendingPathComponent("Documents/b.txt"), encoding: .utf8)
        == "b.txt")
    try FileManager.default.removeItem(at: fixture.folder.appendingPathComponent("b.txt"))
    try await reopened.undoTask(plan.id)
    #expect(
      !FileManager.default.fileExists(
        atPath: fixture.folder.appendingPathComponent("Documents").path))
    #expect(try await reopened.historySnapshot().operations.allSatisfy { $0.state == .undone })
  }

  @Test func rechecksEachLateSourceAndContinuesPastSkips() async throws {
    let fixture = try BatchFixture()
    defer { fixture.remove() }
    for name in ["a.txt", "b.txt", "c.txt", "d.txt"] { try fixture.write(name) }
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let plan = try await coordinator.planSortByType(request: "Sort by type")
    let result = try await coordinator.execute(plan) { progress in
      if progress.processed == 1 {
        try? FileManager.default.removeItem(at: fixture.folder.appendingPathComponent("b.txt"))
        try? Data("later edit".utf8).write(to: fixture.folder.appendingPathComponent("c.txt"))
      }
    }
    #expect(result.changed.map(\.originalName) == ["a.txt", "d.txt"])
    #expect(result.skipped.filter { $0.reason == .staleSource }.map(\.name) == ["b.txt", "c.txt"])
    #expect(!result.isPartial)
    #expect(result.failed.isEmpty)
    #expect(
      try String(contentsOf: fixture.folder.appendingPathComponent("c.txt"), encoding: .utf8)
        == "later edit")
  }

  @Test func journalWriteFailureStopsAndPreservesDurableCompletedUndo() async throws {
    let fixture = try BatchFixture()
    defer { fixture.remove() }
    for name in ["a.txt", "b.txt", "c.txt"] { try fixture.write(name) }
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let plan = try await coordinator.planSortByType(request: "Sort by type")
    let settings = fixture.bookmark.deletingLastPathComponent()
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o700], ofItemAtPath: settings.path)
    }
    let result = try await coordinator.execute(plan) { progress in
      if progress.processed == 1 {
        try? FileManager.default.setAttributes(
          [.posixPermissions: 0o500], ofItemAtPath: settings.path)
      }
    }
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: settings.path)
    #expect(result.changed.map(\.originalName) == ["a.txt"])
    #expect(result.failed.map(\.name) == ["b.txt"])
    #expect(result.unprocessed == ["c.txt"])
    let reopened = TaskCoordinator(bookmarkFile: fixture.bookmark)
    #expect(try await reopened.historySnapshot().operations.count == 1)
    try await reopened.undoTask(plan.id)
    #expect(
      try String(contentsOf: fixture.folder.appendingPathComponent("a.txt"), encoding: .utf8)
        == "a.txt")
  }

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
    #expect(
      !FileManager.default.fileExists(atPath: fixture.folder.appendingPathComponent("Images").path))
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
          await #expect(throws: SortError.busy) { try await coordinator.historySnapshot() }
          await #expect(throws: SortError.busy) {
            try await coordinator.clearHistory(confirmingUndoLoss: true)
          }
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
    #expect(
      try String(
        contentsOf: fixture.folder.appendingPathComponent("Documents/b.txt"), encoding: .utf8)
        == "Documents/b.txt")
    let reopened = TaskCoordinator(bookmarkFile: fixture.bookmark)
    try await reopened.undoTask(plan.id)
    #expect(
      try String(contentsOf: fixture.folder.appendingPathComponent("a.txt"), encoding: .utf8)
        == "a.txt")
  }

  @Test(arguments: [100, 101, 1_000, 1_001])
  func countsDistinctChangesAndLimitsEligibleScope(count: Int) async throws {
    let fixture = try BatchFixture()
    defer { fixture.remove() }
    for index in 0..<count { try fixture.write("file-\(index).txt") }
    try fixture.write(".hidden.txt")
    if count <= 101 {
      try FileManager.default.createDirectory(
        at: fixture.folder.appendingPathComponent("Documents"), withIntermediateDirectories: false)
      try fixture.write("Documents/file-0.txt")
    }
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
      #expect(plan.renameCount == (count <= 101 ? 1 : 0))
      #expect(plan.requiresConfirmation == (count > 100))
      if count > 100 {
        await #expect(throws: SortError.confirmationRequired) {
          try await coordinator.execute(plan)
        }
        if count == 101 {
          let result = try await coordinator.execute(plan, confirmed: true)
          #expect(result.changed.count == 101)
        } else {
          let result = try await Task {
            try await coordinator.execute(plan, confirmed: true) { progress in
              if progress.processed == 1 { withUnsafeCurrentTask { $0?.cancel() } }
            }
          }.value
          #expect(result.changed.count == 1)
          #expect(result.unprocessed.count == 999)
        }
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
    try FileManager.default.removeItem(at: fixture.folder.appendingPathComponent("Images"))
    let plan = try await coordinator.planSortByType(request: "Sort by type")
    try fixture.write("Images")
    await #expect(throws: SortError.conflict) { try await coordinator.execute(plan) }
    #expect(
      !FileManager.default.fileExists(
        atPath: fixture.folder.appendingPathComponent("Documents").path))
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
    #expect(
      FileManager.default.fileExists(
        atPath: fixture.folder.appendingPathComponent("notes.txt").path))
    let result = try await coordinator.execute(plan)
    #expect(result.changed.count == 2)
    #expect(
      try String(
        contentsOf: fixture.folder.appendingPathComponent("Documents/notes (3).txt"),
        encoding: .utf8) == "notes.txt")
    let reopened = TaskCoordinator(bookmarkFile: fixture.bookmark)
    let history = try await reopened.historySnapshot()
    #expect(history.tasks.count == 1)
    #expect(history.tasks.first?.id == plan.id)
    #expect(history.tasks.first?.operations.count == 2)
    #expect(history.operations.contains { $0.resultingPath.hasSuffix("/Documents/notes (3).txt") })
    try await reopened.undoTask(plan.id)
    #expect(
      try String(contentsOf: fixture.folder.appendingPathComponent("notes.txt"), encoding: .utf8)
        == "notes.txt")
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
