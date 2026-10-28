import Foundation
import Testing
import TidyCore

struct HistoryTests {
  @Test func clearRequiresConfirmationAndOnlyDiscardsRecoveryRecordsAcrossReopen() async throws {
    let fixture = try HistoryFixture()
    defer { fixture.remove() }
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let operation = try await coordinator.sortByType(request: "Sort by type")
    let model = fixture.bookmark.deletingLastPathComponent().appendingPathComponent("model.bin")
    try Data("unrelated model".utf8).write(to: model)
    let bookmark = try Data(contentsOf: fixture.bookmark)
    let grant = try Data(contentsOf: fixture.bookmark.appendingPathExtension("write-grant"))
    let directoryBefore = try FileManager.default.contentsOfDirectory(atPath: fixture.folder.path)
    let resultAttributes = try FileManager.default.attributesOfItem(atPath: fixture.result.path)
    await #expect(throws: HistoryError.confirmationRequired) {
      try await coordinator.clearHistory(confirmingUndoLoss: false)
    }
    #expect(try await coordinator.historySnapshot().operations.count == 1)
    try await coordinator.clearHistory(confirmingUndoLoss: true)
    let reopened = TaskCoordinator(bookmarkFile: fixture.bookmark)
    let empty = try await reopened.historySnapshot()
    #expect(empty.operations.isEmpty)
    #expect(empty.recordBytes == 2)
    await #expect(throws: SortError.uncertainIdentity) { try await reopened.undoTask(operation.id) }
    await #expect(throws: SortError.uncertainIdentity) { try await reopened.undoFile(operation.id) }
    #expect(try Data(contentsOf: fixture.result) == fixture.content)
    #expect(!FileManager.default.fileExists(atPath: fixture.source.path))
    #expect(
      try FileManager.default.contentsOfDirectory(atPath: fixture.folder.path) == directoryBefore)
    let after = try FileManager.default.attributesOfItem(atPath: fixture.result.path)
    #expect(
      after[.systemFileNumber] as? NSNumber == resultAttributes[.systemFileNumber] as? NSNumber)
    #expect(after[.modificationDate] as? Date == resultAttributes[.modificationDate] as? Date)
    #expect(try Data(contentsOf: model) == Data("unrelated model".utf8))
    #expect(try Data(contentsOf: fixture.bookmark) == bookmark)
    #expect(try Data(contentsOf: fixture.bookmark.appendingPathExtension("write-grant")) == grant)
  }

  @Test func historyReopensWithPathsOutcomesAndMeasuredRecordStorage() async throws {
    let fixture = try HistoryFixture()
    defer { fixture.remove() }
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    let inventory = try await coordinator.selectFolderForWriting(fixture.folder)
    let operation = try await coordinator.sortByType(request: "Sort by type")
    let reopened = TaskCoordinator(bookmarkFile: fixture.bookmark)
    let history = try await reopened.historySnapshot()
    #expect(history.operations.count == 1)
    #expect(history.operations.first?.id == operation.id)
    #expect(history.operations.first?.originalPath == inventory.folder.path + "/notes.txt")
    #expect(
      history.operations.first?.resultingPath == inventory.folder.path + "/Documents/notes.txt")
    #expect(history.operations.first?.state == .completed)
    #expect(history.recordBytes == Int64(try Data(contentsOf: fixture.journal).count))
    #expect(history.recordBytes > 2)
    #expect(try Data(contentsOf: fixture.result) == fixture.content)
    #expect(
      !String(decoding: try Data(contentsOf: fixture.journal), as: UTF8.self)
        .contains("PRIVATE DOCUMENT CONTENT"))
    try await reopened.undoFile(operation.id)
    #expect(try await reopened.historySnapshot().operations.first?.state == .undone)
    #expect(try Data(contentsOf: fixture.source) == fixture.content)
  }
}

private struct HistoryFixture {
  let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
    .appendingPathComponent("tidy-history-\(UUID())")
  let content = Data("PRIVATE DOCUMENT CONTENT".utf8)
  var folder: URL { root.appendingPathComponent("Selected") }
  var bookmark: URL { root.appendingPathComponent("settings/folder.bookmark") }
  var journal: URL { root.appendingPathComponent("settings/operations.json") }
  var source: URL { folder.appendingPathComponent("notes.txt") }
  var result: URL { folder.appendingPathComponent("Documents/notes.txt") }

  init() throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try content.write(to: source)
  }

  func remove() { try? FileManager.default.removeItem(at: root) }
}
