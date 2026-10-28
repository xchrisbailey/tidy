import Foundation
import Testing
import TidyCore

struct SortAndUndoTests {
  @Test func corruptHistoryCannotTurnATruncatedNameIntoAFileOperation() async throws {
    let fixture = try SortFixture()
    defer { fixture.remove() }
    try Data("keep".utf8).write(to: fixture.source)
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let result = try await coordinator.sortByType(request: "Sort by type")
    try fixture.persistInterrupted(result, state: "completed", originalName: "notes.txt\0other")
    let reopened = TaskCoordinator(bookmarkFile: fixture.bookmark)
    await #expect(throws: SortError.journalUnavailable) { try await reopened.undoHistory() }
    await #expect(throws: SortError.journalUnavailable) { try await reopened.undoFile(result.id) }
    #expect(try Data(contentsOf: fixture.sorted) == Data("keep".utf8))
  }

  @Test func missingResultFolderIsAnIdentityConflictNotAnOccupiedDestination() async throws {
    let fixture = try SortFixture()
    defer { fixture.remove() }
    try Data("keep".utf8).write(to: fixture.source)
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let result = try await coordinator.sortByType(request: "Sort by type")
    let elsewhere = fixture.root.appendingPathComponent("MovedElsewhere")
    try FileManager.default.moveItem(at: fixture.sorted.deletingLastPathComponent(), to: elsewhere)
    let reopened = TaskCoordinator(bookmarkFile: fixture.bookmark)
    await #expect(throws: SortError.uncertainIdentity) { try await reopened.undoFile(result.id) }
    #expect(
      try Data(contentsOf: elsewhere.appendingPathComponent("notes.txt")) == Data("keep".utf8))
    #expect(!FileManager.default.fileExists(atPath: fixture.source.path))
  }

  @Test func concurrentSubmissionsCannotMoveTheSameFileTwice() async throws {
    let fixture = try SortFixture()
    defer { fixture.remove() }
    try Data("keep".utf8).write(to: fixture.source)
    let first = TaskCoordinator(bookmarkFile: fixture.bookmark)
    let second = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await first.selectFolderForWriting(fixture.folder)
    _ = try await second.restoreFolder()
    let successes = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
      for coordinator in [first, second] {
        group.addTask {
          do {
            _ = try await coordinator.sortByType(request: "Sort by type")
            return true
          } catch { return false }
        }
      }
      var count = 0
      for await success in group where success { count += 1 }
      return count
    }
    #expect(successes == 1)
    #expect(try await first.undoHistory().count == 1)
    #expect(try Data(contentsOf: fixture.sorted) == Data("keep".utf8))
  }

  @Test(arguments: [false, true])
  func undoPreservesExistingAndNowNonemptyFolders(existing: Bool) async throws {
    let fixture = try SortFixture()
    defer { fixture.remove() }
    let directory = fixture.sorted.deletingLastPathComponent()
    if existing {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    }
    try Data("keep".utf8).write(to: fixture.source)
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let result = try await coordinator.sortByType(request: "Sort by type")
    if !existing { try Data("other".utf8).write(to: directory.appendingPathComponent("later.txt")) }
    let reopened = TaskCoordinator(bookmarkFile: fixture.bookmark)
    try await reopened.undoFile(result.id)
    #expect(FileManager.default.fileExists(atPath: directory.path))
    #expect(try Data(contentsOf: fixture.source) == Data("keep".utf8))
    if !existing {
      #expect(
        try Data(contentsOf: directory.appendingPathComponent("later.txt")) == Data("other".utf8))
    }
  }

  @Test func undoRefusesSameNameReplacementEvenWithIdenticalContents() async throws {
    let fixture = try SortFixture()
    defer { fixture.remove() }
    let content = Data("same bytes".utf8)
    try content.write(to: fixture.source)
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let result = try await coordinator.sortByType(request: "Sort by type")
    try FileManager.default.removeItem(at: fixture.sorted)
    try content.write(to: fixture.sorted)
    let reopened = TaskCoordinator(bookmarkFile: fixture.bookmark)
    await #expect(throws: SortError.uncertainIdentity) { try await reopened.undoTask(result.id) }
    #expect(try Data(contentsOf: fixture.sorted) == content)
    #expect(!FileManager.default.fileExists(atPath: fixture.source.path))
  }

  @Test(arguments: ["occupied", "symlink", "file"])
  func validatesDestinationBeforeCreatingOrMovingAnything(kind: String) async throws {
    let fixture = try SortFixture()
    defer { fixture.remove() }
    let directory = fixture.sorted.deletingLastPathComponent()
    try Data("keep".utf8).write(to: fixture.source)
    if kind == "occupied" {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
      try Data("occupied".utf8).write(to: fixture.sorted)
    } else if kind == "symlink" {
      try FileManager.default.createSymbolicLink(at: directory, withDestinationURL: fixture.root)
    } else {
      try Data("not a directory".utf8).write(to: directory)
    }
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    await #expect(throws: kind == "file" ? SortError.oneFileRequired : SortError.conflict) {
      try await coordinator.sortByType(request: "Sort by type")
    }
    #expect(try Data(contentsOf: fixture.source) == Data("keep".utf8))
    #expect(try await coordinator.undoHistory().isEmpty)
    if kind == "occupied" { #expect(try Data(contentsOf: fixture.sorted) == Data("occupied".utf8)) }
  }

  @Test func reconcilesInterruptedUndoAndCleansOnlyIdentifiedEmptyTaskFolder() async throws {
    let fixture = try SortFixture()
    defer { fixture.remove() }
    try Data("keep".utf8).write(to: fixture.source)
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let result = try await coordinator.sortByType(request: "Sort by type")
    try FileManager.default.moveItem(at: fixture.sorted, to: fixture.source)
    try fixture.persistInterrupted(result, state: "undoIntent")
    let reopened = TaskCoordinator(bookmarkFile: fixture.bookmark)
    #expect(try await reopened.undoHistory().first?.state == .undone)
    #expect(
      !FileManager.default.fileExists(atPath: fixture.sorted.deletingLastPathComponent().path))
    #expect(try Data(contentsOf: fixture.source) == Data("keep".utf8))
  }

  @Test func reopensDurableIntentWhenMoveFinishedBeforeCompletionWasSaved() async throws {
    let fixture = try SortFixture()
    defer { fixture.remove() }
    try Data("keep".utf8).write(to: fixture.source)
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let result = try await coordinator.sortByType(request: "Sort by type")
    // A persisted intent plus the real resulting file represents a stop before the completion save.
    try fixture.persistInterrupted(result, state: "intent")
    let reopened = TaskCoordinator(bookmarkFile: fixture.bookmark)
    #expect(try await reopened.undoHistory().first?.state == .completed)
    try await reopened.undoTask(result.id)
    #expect(try Data(contentsOf: fixture.source) == Data("keep".utf8))
  }

  @Test func undoFilePreservesLaterEditsAndReportsOccupiedOriginalAfterReopen() async throws {
    let fixture = try SortFixture()
    defer { fixture.remove() }
    try Data("original".utf8).write(to: fixture.source)
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let result = try await coordinator.sortByType(request: "Sort by type")
    let handle = try FileHandle(forWritingTo: fixture.sorted)
    try handle.truncate(atOffset: 0)
    try handle.write(contentsOf: Data("edited later".utf8))
    try handle.close()
    try Data("occupied".utf8).write(to: fixture.source)
    let reopened = TaskCoordinator(bookmarkFile: fixture.bookmark)
    await #expect(throws: SortError.conflict) { try await reopened.undoFile(result.id) }
    #expect(try Data(contentsOf: fixture.source) == Data("occupied".utf8))
    #expect(try Data(contentsOf: fixture.sorted) == Data("edited later".utf8))
    try FileManager.default.removeItem(at: fixture.source)
    try await reopened.undoFile(result.id)
    #expect(try Data(contentsOf: fixture.source) == Data("edited later".utf8))
  }

  @Test func readGrantAndUnsupportedRequestsCannotMutate() async throws {
    let fixture = try SortFixture()
    defer { fixture.remove() }
    try Data("keep".utf8).write(to: fixture.source)
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolder(fixture.folder)
    await #expect(throws: SortError.writeGrantRequired) {
      try await coordinator.sortByType(request: "Sort by type")
    }
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    await #expect(throws: SortError.unsupportedRequest) {
      try await coordinator.sortByType(request: "Rename everything")
    }
    #expect(try Data(contentsOf: fixture.source) == Data("keep".utf8))
    #expect(try await coordinator.undoHistory().isEmpty)
  }

  @Test func refusesReplacementSinceInventoryEvenWhenNameAndSizeMatch() async throws {
    let fixture = try SortFixture()
    defer { fixture.remove() }
    try Data("old".utf8).write(to: fixture.source)
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    try FileManager.default.removeItem(at: fixture.source)
    try Data("new".utf8).write(to: fixture.source)
    await #expect(throws: SortError.staleSource) {
      try await coordinator.sortByType(request: "Sort by type")
    }
    #expect(try Data(contentsOf: fixture.source) == Data("new".utf8))
    #expect(
      !FileManager.default.fileExists(atPath: fixture.sorted.deletingLastPathComponent().path))
  }

  @Test func sortsOneFileAndUndoesAfterReopenWithoutChangingItsContents() async throws {
    let fixture = try SortFixture()
    defer { fixture.remove() }
    let original = Data("private content".utf8)
    try original.write(to: fixture.source)
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let result = try await coordinator.sortByType(request: "Sort by type")
    #expect(result.originalName == "notes.txt")
    #expect(result.destinationFolder == "Documents")
    #expect(!FileManager.default.fileExists(atPath: fixture.source.path))
    #expect(try Data(contentsOf: fixture.sorted) == original)
    let reopened = TaskCoordinator(bookmarkFile: fixture.bookmark)
    let history = try await reopened.undoHistory()
    #expect(history.count == 1)
    #expect(history.first?.state == .completed)
    try await reopened.undoTask(result.id)
    #expect(try Data(contentsOf: fixture.source) == original)
    #expect(
      !FileManager.default.fileExists(atPath: fixture.sorted.deletingLastPathComponent().path))
    #expect(try await reopened.undoHistory().first?.state == .undone)
  }
}

private struct SortFixture {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent("tidy-sort-\(UUID())")
  var folder: URL { root.appendingPathComponent("Selected") }
  var bookmark: URL { root.appendingPathComponent("settings/folder.bookmark") }
  var source: URL { folder.appendingPathComponent("notes.txt") }
  var sorted: URL { folder.appendingPathComponent("Documents/notes.txt") }

  init() throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  }

  func remove() { try? FileManager.default.removeItem(at: root) }

  func persistInterrupted(_ operation: FileOperation, state: String, originalName: String? = nil)
    throws
  {
    let data = try JSONEncoder().encode(operation)
    var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    object["state"] = state
    if let originalName { object["originalName"] = originalName }
    try JSONSerialization.data(withJSONObject: [object]).write(
      to: bookmark.deletingLastPathComponent().appendingPathComponent("operations.json"))
  }
}
