import Foundation
import Testing
import TidyCore

struct DiagnosticTests {
  @Test(arguments: [
    "invalid", "interrupted", "inspection", "ordinary", "recovery", "undo", "contentModelError",
  ])
  func failuresRemainUsefulWithoutPrivateMaterial(kind: String) async throws {
    let fixture = try LanguageFixture()
    defer { fixture.remove() }
    let secret = "Sensitive-\(UUID())"
    let excerpt = "DocumentExcerpt-\(UUID())"
    let source = fixture.folder.appendingPathComponent("\(secret).txt")
    try (Data(excerpt.utf8) + Data([0xff])).write(to: source)
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark) { checkpoint in
      if kind == "interrupted", checkpoint == .afterMove {
        throw NSError(domain: secret, code: 7, userInfo: [NSLocalizedDescriptionKey: excerpt])
      }
    }
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    var expected: String
    switch kind {
    case "invalid":
      await #expect(throws: PlanningError.invalidResponse) {
        _ = try await coordinator.planTask(request: "Sort by type \(secret)") { _, _, _ in
          "{\"nested\":{\"private\":\"\(excerpt)\"}}"
        }
      }
      expected = "invalidPlan"
    case "inspection":
      let request = "Give files readable names from contents"
      let response = try metadataResponse(
        request: request, sort: "none",
        rename: [["kind": "content", "evidence": request, "value": "", "from": ""]])
      guard
        case .plan(let plan) = try await coordinator.planTask(
          request: request, model: { _, _, _ in response })
      else {
        Issue.record("Expected inspection abstention")
        return
      }
      #expect(plan.abstained.count == 1)
      #expect(try await coordinator.execute(plan).changed.isEmpty)
      expected = "inspection_unreadable"
    case "contentModelError":
      try Data("\(excerpt) Private Invoice AB123".utf8).write(to: source)
      _ = try await coordinator.selectFolderForWriting(fixture.folder)
      let request = "Give files readable names from contents"
      let response = try metadataResponse(
        request: request, sort: "none",
        rename: [["kind": "content", "evidence": request, "value": "", "from": ""]])
      await #expect(throws: PlanningError.invalidResponse) {
        _ = try await coordinator.planTask(request: request) { _, input, _ in
          if input.contains("untrustedEvidence") {
            #expect(input.contains(excerpt))
            throw NSError(domain: secret, code: 3, userInfo: [NSLocalizedDescriptionKey: excerpt])
          }
          return response
        }
      }
      expected = "invalidPlan"
    case "ordinary":
      let plan = try await coordinator.planSortByType(request: "Sort by type")
      try Data(excerpt.utf8).write(to: fixture.folder.appendingPathComponent("Documents"))
      await #expect(throws: SortError.conflict) { _ = try await coordinator.execute(plan) }
      expected = "taskFailure"
    case "recovery":
      try Data(excerpt.utf8).write(
        to: fixture.bookmark.deletingLastPathComponent().appendingPathComponent("operations.json"))
      do {
        _ = try await coordinator.recoveryReport()
        Issue.record("Expected recovery failure")
      } catch {}
      expected = "recoveryFailure"
    case "undo":
      let plan = try await coordinator.planSortByType(request: "Sort by type")
      #expect(try await coordinator.execute(plan).changed.count == 1)
      try Data("Occupied".utf8).write(to: source)
      await #expect(throws: SortError.conflict) { try await coordinator.undoTask(plan.id) }
      expected = "recoveryFailure"
    default:
      let plan = try await coordinator.planSortByType(request: "Sort by type")
      let result = try await coordinator.execute(plan)
      #expect(result.isPartial)
      #expect(result.changed.count == 1)
      let reopened = TaskCoordinator(bookmarkFile: fixture.bookmark)
      #expect(try await reopened.recoveryReport().count == 1)
      let recoveredExport = fixture.root.appendingPathComponent("Reopened-\(secret).json")
      try await reopened.exportDiagnostics(to: recoveredExport)
      let recoveredText = try String(contentsOf: recoveredExport, encoding: .utf8)
      #expect(recoveredText.contains("\"history_completed\" : 1"))
      #expect(!recoveredText.contains(secret))
      #expect(!recoveredText.contains(excerpt))
      expected = "interrupted"
    }
    let export = fixture.root.appendingPathComponent("Export-\(secret).json")
    try await coordinator.exportDiagnostics(to: export, modelState: .failed)
    let bytes = try Data(contentsOf: export)
    let text = String(decoding: bytes, as: UTF8.self)
    for marker in [secret, excerpt, fixture.root.path, export.path] {
      #expect(!text.contains(marker))
    }
    let object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    #expect((object["counters"] as? [String: Int])?[expected] == 1)
    #expect(object["modelState"] as? String == "failed")
    // Undo records may retain ordinary paths/names, but never excerpts, requests or errors.
    if kind != "recovery" {
      let settings = fixture.bookmark.deletingLastPathComponent()
      for url in try FileManager.default.contentsOfDirectory(
        at: settings, includingPropertiesForKeys: nil)
      {
        #expect(!String(decoding: try Data(contentsOf: url), as: UTF8.self).contains(excerpt))
      }
    }
    do {
      try await coordinator.exportDiagnostics(to: export.appendingPathComponent(secret))
      Issue.record("Expected export write failure")
    } catch {
      #expect(error is DiagnosticExportError)
      #expect(!error.localizedDescription.contains(secret))
      #expect(!error.localizedDescription.contains(export.path))
    }
  }

  @Test func modelFailureExportsOnlySafeCodesToAnActualArtifact() async throws {
    let fixture = try LanguageFixture()
    defer { fixture.remove() }
    let secret = "PrivateMarker-\(UUID())"
    try Data("Document-\(secret)".utf8).write(
      to: fixture.folder.appendingPathComponent("Filename-\(secret).txt"))
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    do {
      _ = try await coordinator.planTask(request: "Sort by type \(secret)") { _, _, _ in
        throw NSError(
          domain: secret, code: 1,
          userInfo: [
            NSLocalizedDescriptionKey: secret,
            NSUnderlyingErrorKey: NSError(domain: fixture.folder.path, code: 2),
          ])
      }
      Issue.record("Expected failure")
    } catch {}
    let export = fixture.root.appendingPathComponent("Export-\(secret).json")
    try await coordinator.exportDiagnostics(to: export)
    let bytes = try Data(contentsOf: export)
    let text = String(decoding: bytes, as: UTF8.self)
    #expect(!text.contains(secret))
    #expect(!text.contains(fixture.root.path))
    let object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    #expect(Set(object.keys) == ["schemaVersion", "platform", "counters", "modelState"])
    let counters = try #require(object["counters"] as? [String: Int])
    #expect(counters["modelFailure"] == 1)
    #expect(try await coordinator.historySnapshot().operations.isEmpty)
  }
}
