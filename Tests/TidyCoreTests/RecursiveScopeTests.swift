import Darwin
import Foundation
import Testing
import TidyCore

struct RecursiveScopeTests {
  @Test(arguments: ["../Outside", "/Outside", "Nested/Outside"])
  func recursiveDestinationsCannotBecomeModelSuppliedPaths(destination: String) async throws {
    let fixture = try LanguageFixture()
    defer { fixture.remove() }
    try FileManager.default.createDirectory(
      at: fixture.folder.appendingPathComponent("Nested"), withIntermediateDirectories: true)
    try fixture.write("Nested/report.txt")
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let request = "Move files including subfolders into ‘\(destination)’"
    let response = try metadataResponse(request: request, sort: "folder", value: destination)
    await #expect(throws: PlanningError.invalidResponse) {
      try await coordinator.planTask(request: request, model: { _, _, _ in response })
    }
    #expect(
      try String(
        contentsOf: fixture.folder.appendingPathComponent("Nested/report.txt"), encoding: .utf8)
        == "fixture")
    #expect(try await coordinator.undoHistory().isEmpty)
  }

  @Test func destinationAncestorSwapAtMoveCannotEscapePinnedScope() async throws {
    let fixture = try LanguageFixture()
    defer { fixture.remove() }
    for folder in ["Nested", "Documents"] {
      try FileManager.default.createDirectory(
        at: fixture.folder.appendingPathComponent(folder), withIntermediateDirectories: true)
    }
    try fixture.write("Nested/report.txt")
    let detached = fixture.root.appendingPathComponent("DetachedDestination")
    let coordinator = TaskCoordinator(
      bookmarkFile: fixture.bookmark,
      operationCheckpoint: { point in
        if point == .beforeMove {
          try FileManager.default.moveItem(
            at: fixture.folder.appendingPathComponent("Documents"), to: detached)
          try FileManager.default.createSymbolicLink(
            at: fixture.folder.appendingPathComponent("Documents"), withDestinationURL: detached)
        }
      })
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let request = "Sort by type including subfolders"
    let response = try metadataResponse(request: request)
    let outcome = try await coordinator.planTask(request: request, model: { _, _, _ in response })
    guard case .plan(let plan) = outcome else {
      Issue.record("Expected recursive plan")
      return
    }
    let result = try await coordinator.execute(plan)
    #expect(result.changed.isEmpty)
    #expect(result.failed.count == 1)
    #expect(try FileManager.default.contentsOfDirectory(atPath: detached.path).isEmpty)
    #expect(
      try String(
        contentsOf: fixture.folder.appendingPathComponent("Nested/report.txt"), encoding: .utf8)
        == "fixture")
  }

  @Test(arguments: [
    "Sort by type; subfolders?", "Sort by type including subfolders but not recursively",
    "Sort by type in subfolder ‘A’",
    "Sort by type including subfolders named ‘A’",
    "Sort by type including subfolders ‘A’ and ‘B’",
  ])
  func ambiguousScopeClarifiesWithoutInference(request: String) async throws {
    let fixture = try LanguageFixture()
    defer { fixture.remove() }
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let outcome = try await coordinator.planTask(
      request: request,
      model: { _, _, _ in
        Issue.record("Ambiguous scope must not reach inference")
        return "{}"
      })
    guard case .clarification(let question) = outcome else {
      Issue.record("Expected scope clarification")
      return
    }
    #expect(question.contains("subfolders"))
    #expect(try await coordinator.undoHistory().isEmpty)
  }

  @Test func recursiveExclusionsPruneEntireUnsafeTrees() async throws {
    let fixture = try LanguageFixture()
    defer { fixture.remove() }
    for folder in [
      "Nested/ordinary", "Nested/.hidden", "Nested/Example.app", "Nested/pending.download",
      "Nested/cloud.icloud",
    ] {
      try FileManager.default.createDirectory(
        at: fixture.folder.appendingPathComponent(folder), withIntermediateDirectories: true)
      try fixture.write(folder + "/secret.txt")
    }
    try fixture.write("Nested/.hidden.txt")
    try fixture.write("Nested/file.part")
    try fixture.write("Nested/file.icloud")
    try fixture.write("Nested/hard.txt")
    try FileManager.default.linkItem(
      at: fixture.folder.appendingPathComponent("Nested/hard.txt"),
      to: fixture.folder.appendingPathComponent("Nested/hard-again.txt"))
    try FileManager.default.createSymbolicLink(
      at: fixture.folder.appendingPathComponent("Nested/link"), withDestinationURL: fixture.root)
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let request = "Sort by type including subfolders"
    let response = try metadataResponse(request: request)
    let outcome = try await coordinator.planTask(request: request, model: { _, _, _ in response })
    guard case .plan(let plan) = outcome else {
      Issue.record("Expected eligible recursive plan")
      return
    }
    #expect(plan.changes.map(\.originalName) == ["Nested/ordinary/secret.txt"])
    #expect(plan.skipped.count == 10)
    #expect(try await coordinator.execute(plan).changed.count == 1)
    #expect(
      try String(
        contentsOf: fixture.folder.appendingPathComponent("Nested/Example.app/secret.txt"),
        encoding: .utf8) == "fixture")
    try await coordinator.undoTask(plan.id)
  }

  @Test func nestedRenameStaysInOriginalParentAndUndoRefusesOccupiedOriginal() async throws {
    let fixture = try LanguageFixture()
    defer { fixture.remove() }
    try FileManager.default.createDirectory(
      at: fixture.folder.appendingPathComponent("Preserve THIS/deep"),
      withIntermediateDirectories: true)
    try fixture.write("Preserve THIS/deep/REPORT 2026-10-28 AB123.TXT")
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let request = "Lowercase filenames and prepend ‘Filed-’, including subfolders"
    let response = try metadataResponse(
      request: request, sort: "none",
      rename: [
        ["kind": "lowercase", "evidence": "Lowercase filenames", "value": "", "from": ""],
        ["kind": "prefix", "evidence": "prepend ‘Filed-’", "value": "Filed-", "from": ""],
      ])
    let outcome = try await coordinator.planTask(request: request, model: { _, _, _ in response })
    guard case .plan(let plan) = outcome else {
      Issue.record("Expected nested rename")
      return
    }
    #expect(plan.renameCount == 1)
    #expect(plan.moveCount == 0)
    #expect(try await coordinator.execute(plan).changed.count == 1)
    let renamed = fixture.folder.appendingPathComponent(
      "Preserve THIS/deep/Filed-report 2026-10-28 AB123.TXT")
    #expect(try String(contentsOf: renamed, encoding: .utf8) == "fixture")
    try fixture.write("Preserve THIS/deep/REPORT 2026-10-28 AB123.TXT")
    let reopened = TaskCoordinator(bookmarkFile: fixture.bookmark)
    await #expect(throws: SortError.conflict) { try await reopened.undoTask(plan.id) }
    try FileManager.default.removeItem(
      at: fixture.folder.appendingPathComponent("Preserve THIS/deep/REPORT 2026-10-28 AB123.TXT"))
    try await reopened.undoTask(plan.id)
    #expect(
      FileManager.default.fileExists(
        atPath: fixture.folder.appendingPathComponent(
          "Preserve THIS/deep/REPORT 2026-10-28 AB123.TXT"
        ).path))
  }

  @Test(arguments: ["beforeExecution", "beforeMove", "undo"])
  func ancestorSwapCannotRedirectMutationOrUndo(stage: String) async throws {
    let fixture = try LanguageFixture()
    defer { fixture.remove() }
    let nested = fixture.folder.appendingPathComponent("Nested")
    let detached = fixture.root.appendingPathComponent("Detached")
    let unrelated = fixture.root.appendingPathComponent("Unrelated")
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
    try fixture.write("Nested/report.txt")
    try Data("unrelated".utf8).write(to: unrelated.appendingPathComponent("report.txt"))
    let swap: @Sendable () throws -> Void = {
      try FileManager.default.moveItem(at: nested, to: detached)
      try FileManager.default.createSymbolicLink(at: nested, withDestinationURL: unrelated)
    }
    let coordinator = TaskCoordinator(
      bookmarkFile: fixture.bookmark,
      operationCheckpoint: { point in
        if (stage == "beforeMove" && point == .beforeMove)
          || (stage == "undo" && point == .undoIntentSaved)
        {
          try swap()
        }
      })
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let request = "Sort by type including subfolders"
    let response = try metadataResponse(request: request)
    let outcome = try await coordinator.planTask(request: request, model: { _, _, _ in response })
    guard case .plan(let plan) = outcome else {
      Issue.record("Expected recursive plan")
      return
    }
    if stage == "beforeExecution" {
      try swap()
      await #expect(throws: SortError.uncertainIdentity) { try await coordinator.execute(plan) }
    } else if stage == "beforeMove" {
      let result = try await coordinator.execute(plan)
      #expect(result.changed.isEmpty)
      #expect(result.failed.count == 1)
      #expect(
        try String(contentsOf: detached.appendingPathComponent("report.txt"), encoding: .utf8)
          == "fixture")
    } else {
      #expect(try await coordinator.execute(plan).changed.count == 1)
      await #expect(throws: SortError.uncertainIdentity) { try await coordinator.undoTask(plan.id) }
      #expect(
        try String(
          contentsOf: fixture.folder.appendingPathComponent("Documents/report.txt"), encoding: .utf8
        ) == "fixture")
      let reopened = TaskCoordinator(bookmarkFile: fixture.bookmark)
      #expect(try await reopened.recoveryReport().first?.status == .uncertain)
    }
    #expect(
      try String(contentsOf: unrelated.appendingPathComponent("report.txt"), encoding: .utf8)
        == "unrelated")
  }

  @Test func recursiveLimitsConfirmationStaleChecksProgressAndCancellationCoverWholeScope()
    async throws
  {
    let fixture = try LanguageFixture()
    defer { fixture.remove() }
    for directory in ["A", "B"] {
      try FileManager.default.createDirectory(
        at: fixture.folder.appendingPathComponent(directory), withIntermediateDirectories: true)
    }
    for index in 0..<101 { try fixture.write("\(index < 50 ? "A" : "B")/file\(index).txt") }
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let request = "Sort by type including subfolders"
    let response = try metadataResponse(
      request: request, decisions: Array(repeating: "apply", count: 101))
    let outcome = try await coordinator.planTask(request: request, model: { _, _, _ in response })
    guard case .plan(let plan) = outcome else {
      Issue.record("Expected whole-scope plan")
      return
    }
    #expect(plan.changedCount == 101)
    #expect(plan.moveCount == 101)
    #expect(plan.renameCount == 0)
    await #expect(throws: SortError.confirmationRequired) { try await coordinator.execute(plan) }
    let stale = try #require(plan.changes.first).originalName
    try Data("later edit".utf8).write(to: fixture.folder.appendingPathComponent(stale))
    let task = Task {
      try await coordinator.execute(plan, confirmed: true) { progress in
        #expect(progress.total == 101)
        if progress.processed == 3 { withUnsafeCurrentTask { $0?.cancel() } }
      }
    }
    let result = try await task.value
    #expect(result.cancelled)
    #expect(result.changed.count == 2)
    #expect(result.skipped.filter { $0.reason == .staleSource }.count == 1)
    #expect(result.unprocessed.count == 98)
    let reopened = TaskCoordinator(bookmarkFile: fixture.bookmark)
    try await reopened.undoTask(plan.id)
    #expect(try await reopened.undoHistory().allSatisfy { $0.state == .undone })
    for index in 101..<1_001 { try fixture.write("B/file\(index).txt") }
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    await #expect(throws: SortError.scopeTooLarge) {
      try await coordinator.planTask(
        request: request,
        model: { _, _, _ in
          Issue.record("Over-limit recursive inventory must not reach inference")
          return "{}"
        })
    }
  }

  @Test(arguments: [
    "Sort by type", "Sort by type; do not include subfolders",
    "Sort by type without including files from subfolders",
  ])
  func defaultAndNegatedScopeLeaveNestedFilesUntouched(request: String) async throws {
    let fixture = try LanguageFixture()
    defer { fixture.remove() }
    try FileManager.default.createDirectory(
      at: fixture.folder.appendingPathComponent("Nested"), withIntermediateDirectories: true)
    try fixture.write("top.txt")
    try fixture.write("Nested/deep.txt")
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let response = try metadataResponse(request: request)
    let outcome = try await coordinator.planTask(request: request, model: { _, _, _ in response })
    guard case .plan(let plan) = outcome else {
      Issue.record("Expected direct-child plan")
      return
    }
    #expect(plan.changedCount == 1)
    #expect(try await coordinator.execute(plan).changed.count == 1)
    #expect(
      try String(
        contentsOf: fixture.folder.appendingPathComponent("Nested/deep.txt"), encoding: .utf8)
        == "fixture")
  }

  @Test func explicitSubfoldersSortCollisionsPreserveFoldersAndReopenedUndo() async throws {
    let fixture = try LanguageFixture()
    defer { fixture.remove() }
    for folder in ["A/deep", "B", "Documents"] {
      try FileManager.default.createDirectory(
        at: fixture.folder.appendingPathComponent(folder), withIntermediateDirectories: true)
    }
    for name in ["A/deep/report.txt", "B/report.txt", "Documents/report.txt"] {
      try fixture.write(name)
    }
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let request = "Sort by type including subfolders"
    let response = try metadataResponse(request: request, decisions: [])
      .replacingOccurrences(of: "\"files\":[]", with: "\"files\":\"all\"")
    let outcome = try await coordinator.planTask(
      request: request,
      model: { _, input, _ in
        let object = try JSONSerialization.jsonObject(with: Data(input.utf8))
        #expect((object as? [String: Any])?["request"] as? String == request)
        #expect((object as? [String: Any])?["metadata"] == nil)
        return response
      })
    guard case .plan(let plan) = outcome else {
      Issue.record("Explicit subfolder inclusion must produce a recursive plan")
      return
    }
    #expect(plan.changedCount == 2)
    let result = try await coordinator.execute(plan)
    #expect(result.changed.count == 2)
    for name in ["Documents/report.txt", "Documents/report (2).txt", "Documents/report (3).txt"] {
      #expect(
        FileManager.default.fileExists(atPath: fixture.folder.appendingPathComponent(name).path))
    }
    let reopened = TaskCoordinator(bookmarkFile: fixture.bookmark)
    try await reopened.undoTask(plan.id)
    for name in ["A/deep/report.txt", "B/report.txt", "Documents/report.txt"] {
      #expect(
        try String(contentsOf: fixture.folder.appendingPathComponent(name), encoding: .utf8)
          == "fixture")
    }
    #expect(
      FileManager.default.fileExists(atPath: fixture.folder.appendingPathComponent("A/deep").path))
  }
}
