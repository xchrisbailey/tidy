import Foundation
import Testing
import TidyCore

struct NaturalLanguageTests {
  @Test func successiveModelRenameAndSortRequireNewestUndoFirst() async throws {
    let fixture = try LanguageFixture()
    defer { fixture.remove() }
    try fixture.write("Invoice 2026-10-28 AB123.TXT")
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let rename = try await coordinator.planTask(
      request: "Rename files replacing spaces with hyphens",
      model: { _, _, _ in
        #"{"status":"plan","message":"","files":[{"sourceID":"f0","disposition":"change","folder":".","name":"Invoice-2026-10-28-AB123.TXT"}]}"#
      })
    guard case .plan(let first) = rename else {
      Issue.record("Expected rename")
      return
    }
    _ = try await coordinator.execute(first)
    _ = try await coordinator.restoreFolder()
    let sort = try await coordinator.planTask(
      request: "Sort by type",
      model: { _, _, _ in
        #"{"status":"plan","message":"","files":[{"sourceID":"f0","disposition":"change","folder":"Documents","name":"Invoice-2026-10-28-AB123.TXT"}]}"#
      })
    guard case .plan(let second) = sort else {
      Issue.record("Expected sort")
      return
    }
    _ = try await coordinator.execute(second)
    let reopened = TaskCoordinator(bookmarkFile: fixture.bookmark)
    await #expect(throws: SortError.newerOperation) { try await reopened.undoTask(first.id) }
    try await reopened.undoTask(second.id)
    try await reopened.undoTask(first.id)
    #expect(
      try String(
        contentsOf: fixture.folder.appendingPathComponent("Invoice 2026-10-28 AB123.TXT"),
        encoding: .utf8) == "fixture")
  }

  @Test func modelPlanRetainsLargeTaskConfirmationAndCancellation() async throws {
    let fixture = try LanguageFixture()
    defer { fixture.remove() }
    for index in 0..<101 { try fixture.write("File \(index).txt") }
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    let inventory = try await coordinator.selectFolderForWriting(fixture.folder)
    let files = inventory.candidateFiles.sorted { $0.name < $1.name }.enumerated().map {
      index, item in
      "{\"sourceID\":\"f\(index)\",\"disposition\":\"change\",\"folder\":\".\",\"name\":\"\(item.name.replacingOccurrences(of: " ", with: "-"))\"}"
    }.joined(separator: ",")
    let response = "{\"status\":\"plan\",\"message\":\"\",\"files\":[\(files)]}"
    let outcome = try await coordinator.planTask(
      request: "Rename files replacing spaces with hyphens", model: { _, _, _ in response })
    guard case .plan(let plan) = outcome else {
      Issue.record("Expected rename plan")
      return
    }
    #expect(plan.changedCount == 101)
    #expect(plan.renameCount == 101)
    #expect(plan.moveCount == 0)
    await #expect(throws: SortError.confirmationRequired) { try await coordinator.execute(plan) }
    #expect(try await coordinator.undoHistory().isEmpty)
    let execution = Task {
      try await coordinator.execute(plan, confirmed: true) { progress in
        if progress.processed == 1 { withUnsafeCurrentTask { $0?.cancel() } }
      }
    }
    let result = try await execution.value
    #expect(result.changed.count == 1)
    #expect(result.cancelled)
    #expect(result.unprocessed.count == 100)
    let reopened = TaskCoordinator(bookmarkFile: fixture.bookmark)
    try await reopened.undoTask(plan.id)
    #expect(
      FileManager.default.fileExists(
        atPath: fixture.folder.appendingPathComponent("File 0.txt").path))
  }

  @Test func cancellationDuringInferenceRejectsOutputAndPreventsGrantChanges() async throws {
    let fixture = try LanguageFixture()
    defer { fixture.remove() }
    try fixture.write("a.txt")
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let task = Task {
      try await coordinator.planTask(
        request: "Sort by type",
        model: { _, _, _ in
          await #expect(throws: SortError.busy) { try await coordinator.restoreFolder() }
          withUnsafeCurrentTask { $0?.cancel() }
          return
            #"{"status":"plan","message":"","files":[{"sourceID":"f0","disposition":"change","folder":"Documents","name":"a.txt"}]}"#
        })
    }
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(try await coordinator.undoHistory().isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.folder.path) == ["a.txt"])
  }

  @Test(arguments: [
    "not JSON", "{\"status\":\"plan\",\"message\":\"\",\"files\":[]}",
    #"{"status":"plan","message":"","files":[{"sourceID":"f9","disposition":"change","folder":"Documents","name":"a.txt"}]}"#,
    #"{"status":"plan","message":"","files":[{"sourceID":"f0","disposition":"change","folder":"../outside","name":"a.txt"}]}"#,
    #"{"status":"plan","message":"","files":[{"sourceID":"f0","disposition":"change","folder":"Documents","name":"invented.txt"}]}"#,
    #"{"status":"plan","status":"plan","message":"","files":[{"sourceID":"f0","disposition":"change","folder":"Documents","name":"a.txt"}]}"#,
    #"{"status":"plan","message":"","files":[{"sourceID":"f0","disposition":"delete","folder":"Documents","name":"a.txt"}]}"#,
    #"{"status":"plan","message":"","files":[{"sourceID":"f0","disposition":"change","folder":"Documents","name":"a.txt"},{"sourceID":"f0","disposition":"change","folder":"Documents","name":"a.txt"}]}"#,
  ])
  func malformedAndUnauthorizedPlansCannotMutate(response: String) async throws {
    let fixture = try LanguageFixture()
    defer { fixture.remove() }
    try fixture.write("a.txt")
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let responses = ResponseSequence([response])
    await #expect(throws: PlanningError.invalidResponse) {
      try await coordinator.planTask(
        request: "Sort by type", model: { _, _, _ in await responses.next() })
    }
    #expect(await responses.count == 2)
    #expect(try await coordinator.undoHistory().isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.folder.path) == ["a.txt"])
  }

  @Test func replacementCanSucceedAndClarificationDoesNotMutate() async throws {
    let fixture = try LanguageFixture()
    defer { fixture.remove() }
    try fixture.write("a.txt")
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let responses = ResponseSequence([
      "{",
      #"{"status":"plan","message":"","files":[{"sourceID":"f0","disposition":"change","folder":"Documents","name":"a.txt"}]}"#,
    ])
    let outcome = try await coordinator.planTask(
      request: "Sort by type", model: { _, _, _ in await responses.next() })
    guard case .plan(let plan) = outcome else {
      Issue.record("Expected replacement plan")
      return
    }
    #expect(plan.changedCount == 1)
    #expect(await responses.count == 2)
    let clarification = try await coordinator.planTask(
      request: "Organize my files",
      model: { _, _, _ in
        Issue.record("Must clarify first")
        return "{}"
      })
    guard case .clarification = clarification else {
      Issue.record("Expected clarification")
      return
    }
    let modelClarification = try await coordinator.planTask(
      request: "Sort by type",
      model: { _, _, _ in #"{"status":"clarification","message":"Which type grouping?","files":[]}"#
      })
    guard case .clarification = modelClarification else {
      Issue.record("Expected model clarification")
      return
    }
    #expect(try await coordinator.undoHistory().isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.folder.path) == ["a.txt"])
  }

  @Test func invalidEnvelopeGetsExactlyOneReplacementAndNeverMutates() async throws {
    let fixture = try LanguageFixture()
    defer { fixture.remove() }
    try fixture.write("a.txt")
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let responses = ResponseSequence([
      #"{"status":"plan","message":"","files":[{"sourceID":"f0","disposition":"change","folder":"Documents","name":"a.txt","delete":true}]}"#,
      #"{"status":"plan","message":"","files":[]}"#,
    ])
    await #expect(throws: PlanningError.invalidResponse) {
      try await coordinator.planTask(
        request: "Sort by type",
        model: { _, _, limit in
          #expect(limit == 2048)
          return await responses.next()
        })
    }
    #expect(await responses.count == 2)
    #expect(try await coordinator.undoHistory().isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.folder.path) == ["a.txt"])
  }

  @Test func mixedUnsupportedRequestDeclinesWholeWithoutCallingModel() async throws {
    let fixture = try LanguageFixture()
    defer { fixture.remove() }
    try fixture.write("a.txt")
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let outcome = try await coordinator.planTask(
      request: "Sort by type and delete duplicates",
      model: { _, _, _ in
        Issue.record("Unsupported request must not reach model")
        return "{}"
      })
    guard case .unsupported(let reason) = outcome else {
      Issue.record("Must decline whole mixed request")
      return
    }
    #expect(reason.contains("Sort by type"))
    #expect(try await coordinator.undoHistory().isEmpty)
    #expect(
      FileManager.default.fileExists(atPath: fixture.folder.appendingPathComponent("a.txt").path))
  }

  @Test func renamePreservesExtensionDateIdentifierAndUnchangedIsNotAbstention() async throws {
    let fixture = try LanguageFixture()
    defer { fixture.remove() }
    for name in ["Invoice 2026-10-28 AB123.TXT", "Keep.pdf", "Unknown.xyz"] {
      try fixture.write(name)
    }
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let outcome = try await coordinator.planTask(
      request: "Rename files replacing spaces with hyphens",
      model: { _, _, _ in
        #"{"status":"plan","message":"","files":[{"sourceID":"f0","disposition":"change","folder":".","name":"Invoice-2026-10-28-AB123.TXT"},{"sourceID":"f1","disposition":"unchanged","folder":".","name":"Keep.pdf"},{"sourceID":"f2","disposition":"abstain","folder":".","name":"Unknown.xyz"}]}"#
      })
    guard case .plan(let plan) = outcome else {
      Issue.record("Expected rename plan")
      return
    }
    #expect(plan.moveCount == 0)
    let result = try await coordinator.execute(plan)
    #expect(result.changed.count == 1)
    #expect(result.unchanged.map(\.name) == ["Keep.pdf"])
    #expect(result.abstained.map(\.name) == ["Unknown.xyz"])
    let reopened = TaskCoordinator(bookmarkFile: fixture.bookmark)
    try await reopened.undoTask(plan.id)
    #expect(
      try String(
        contentsOf: fixture.folder.appendingPathComponent("Invoice 2026-10-28 AB123.TXT"),
        encoding: .utf8) == "fixture")
  }

  @Test func localPlanExecutesAndReopensUndo() async throws {
    let fixture = try LanguageFixture()
    defer { fixture.remove() }
    try fixture.write("Invoice 2026-10-28 AB123.txt")
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let response =
      #"{"status":"plan","message":"","files":[{"sourceID":"f0","disposition":"change","folder":"Documents","name":"Invoice 2026-10-28 AB123.txt"}]}"#
    let outcome = try await coordinator.planTask(
      request: "Please organize my files by type", model: { _, _, _ in response })
    guard case .plan(let plan) = outcome else {
      Issue.record("Expected a complete plan")
      return
    }
    let result = try await coordinator.execute(plan)
    #expect(result.changed.count == 1)
    let reopened = TaskCoordinator(bookmarkFile: fixture.bookmark)
    try await reopened.undoTask(plan.id)
    #expect(
      try String(
        contentsOf: fixture.folder.appendingPathComponent("Invoice 2026-10-28 AB123.txt"),
        encoding: .utf8) == "fixture")
  }
}

actor ResponseSequence {
  let responses: [String]
  var count = 0
  init(_ responses: [String]) { self.responses = responses }
  func next() -> String {
    defer { count += 1 }
    return responses[min(count, responses.count - 1)]
  }
}

struct LanguageFixture: Sendable {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "tidy-language-\(UUID())")
  var folder: URL { root.appendingPathComponent("Selected") }
  var bookmark: URL { root.appendingPathComponent("settings/folder.bookmark") }
  init() throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  }
  func write(_ name: String) throws {
    try Data("fixture".utf8).write(to: folder.appendingPathComponent(name))
  }
  func remove() { try? FileManager.default.removeItem(at: root) }
}
