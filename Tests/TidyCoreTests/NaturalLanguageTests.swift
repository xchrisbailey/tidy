import Foundation
import Testing
import TidyCore

struct NaturalLanguageTests {
  @Test(arguments: [1_000, 1_001])
  func compactIntentRetainsWholeScopeCeiling(count: Int) async throws {
    let fixture = try LanguageFixture()
    defer { fixture.remove() }
    for index in 0..<count { try fixture.write("file-\(index).txt") }
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let response = try metadataResponse(request: "Sort by type", decisions: [])
      .replacingOccurrences(of: "\"files\":[]", with: "\"files\":\"all\"")
    if count == 1_001 {
      await #expect(throws: SortError.scopeTooLarge) {
        try await coordinator.planTask(request: "Sort by type") { _, _, _ in
          Issue.record("Oversized scope must not reach inference")
          return response
        }
      }
    } else {
      let outcome = try await coordinator.planTask(request: "Sort by type") { _, input, _ in
        #expect(input.utf8.count < 1_024)
        return response
      }
      guard case .plan(let plan) = outcome else {
        Issue.record("Expected whole plan")
        return
      }
      #expect(plan.changedCount == 1_000)
      #expect(plan.requiresConfirmation)
    }
    #expect(try await coordinator.undoHistory().isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.folder.path).count == count)
  }

  @Test func compactIntentExpandsEveryCapturedFileBeforeAnyMutation() async throws {
    let fixture = try LanguageFixture()
    defer { fixture.remove() }
    for index in 0..<100 { try fixture.write("Download \(index).txt") }
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let response = try metadataResponse(request: "Sort by type", decisions: [])
      .replacingOccurrences(of: "\"files\":[]", with: "\"files\":\"all\"")
    let outcome = try await coordinator.planTask(request: "Sort by type") { _, input, _ in
      // The runtime boundary must stay bounded independently of the selected inventory size.
      #expect(input.utf8.count < 1_024)
      return response
    }
    guard case .plan(let plan) = outcome else {
      Issue.record("Expected full plan")
      return
    }
    #expect(plan.changedCount == 100)
    #expect(plan.moveCount == 100)
    #expect(plan.renameCount == 0)
    #expect(!plan.requiresConfirmation)
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.folder.path).count == 100)
    let result = try await coordinator.execute(plan)
    #expect(result.changed.count == 100)
    try await TaskCoordinator(bookmarkFile: fixture.bookmark).undoTask(plan.id)
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.folder.path).count == 100)
  }

  @Test func successiveModelRenameAndSortRequireNewestUndoFirst() async throws {
    let fixture = try LanguageFixture()
    defer { fixture.remove() }
    try fixture.write("Invoice 2026-10-28 AB123.TXT")
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let renameRequest = "Rename files replacing spaces with hyphens"
    let renameResponse = try metadataResponse(
      request: renameRequest, sort: "none", rename: [separatorRule(evidence: renameRequest)])
    let rename = try await coordinator.planTask(
      request: renameRequest, model: { _, _, _ in renameResponse })
    guard case .plan(let first) = rename else {
      Issue.record("Expected rename")
      return
    }
    _ = try await coordinator.execute(first)
    _ = try await coordinator.restoreFolder()
    let sortResponse = try metadataResponse(request: "Sort by type")
    let sort = try await coordinator.planTask(
      request: "Sort by type", model: { _, _, _ in sortResponse })
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
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let request = "Rename files replacing spaces with hyphens"
    let response = try metadataResponse(
      request: request, sort: "none", rename: [separatorRule(evidence: request)],
      decisions: []
    )
    .replacingOccurrences(of: "\"files\":[]", with: "\"files\":\"all\"")
    let outcome = try await coordinator.planTask(request: request, model: { _, _, _ in response })
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
    let response = try metadataResponse(request: "Sort by type")
    let task = Task {
      try await coordinator.planTask(
        request: "Sort by type",
        model: { _, _, _ in
          await #expect(throws: SortError.busy) { try await coordinator.restoreFolder() }
          withUnsafeCurrentTask { $0?.cancel() }
          return response
        })
    }
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(try await coordinator.undoHistory().isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.folder.path) == ["a.txt"])
  }

  @Test(arguments: [
    "malformed", "missing", "invented", "duplicateID", "duplicateKey", "extra", "delete", "rawPath",
  ])
  func malformedAndUnauthorizedPlansCannotMutate(kind: String) async throws {
    let fixture = try LanguageFixture()
    defer { fixture.remove() }
    try fixture.write("a.txt")
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    var response = try metadataResponse(request: "Sort by type")
    switch kind {
    case "malformed": response = "{"
    case "missing": response = try metadataResponse(request: "Sort by type", decisions: [])
    case "invented": response = response.replacingOccurrences(of: "f0", with: "f9")
    case "duplicateID":
      response = try metadataResponse(request: "Sort by type", decisions: ["apply", "apply"])
        .replacingOccurrences(of: "f1", with: "f0")
    case "duplicateKey":
      response = response.replacingOccurrences(
        of: "\"status\":\"plan\"", with: "\"status\":\"plan\",\"status\":\"plan\"")
    case "extra":
      response = response.replacingOccurrences(
        of: "\"status\":\"plan\"", with: "\"delete\":true,\"status\":\"plan\"")
    case "delete": response = response.replacingOccurrences(of: "\"apply\"", with: "\"delete\"")
    default:
      response = response.replacingOccurrences(
        of: "\"sourceID\":\"f0\"", with: "\"sourceID\":\"f0\",\"folder\":\"../outside\"")
    }
    let responses = ResponseSequence([response])
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

  @Test func replacementCanSucceedAndClarificationDoesNotMutate() async throws {
    let fixture = try LanguageFixture()
    defer { fixture.remove() }
    try fixture.write("a.txt")
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let response = try metadataResponse(request: "Sort by type")
    let responses = ResponseSequence(["{", response])
    let outcome = try await coordinator.planTask(
      request: "Sort by type", model: { _, _, _ in await responses.next() })
    guard case .plan(let plan) = outcome else {
      Issue.record("Expected replacement plan")
      return
    }
    #expect(plan.changedCount == 1)
    #expect(await responses.count == 2)
    let clarification = try metadataResponse(
      request: "Organize my files", status: "clarification", sort: "none", decisions: [],
      message: "Which sorting rule would you like?")
    let clarified = try await coordinator.planTask(
      request: "Organize my files", model: { _, _, _ in clarification })
    guard case .clarification = clarified else {
      Issue.record("Expected clarification")
      return
    }
    let unsupportedRequest = "Sort by type and translate these reports into French"
    let refusal = try metadataResponse(
      request: unsupportedRequest, status: "unsupported", sort: "none", decisions: [],
      message: "Translation is not a metadata sorting or renaming task.")
    let refused = try await coordinator.planTask(
      request: unsupportedRequest, model: { _, _, _ in refusal })
    guard case .unsupported = refused else {
      Issue.record("Expected the model to decline the entire mixed request")
      return
    }
    #expect(try await coordinator.undoHistory().isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.folder.path) == ["a.txt"])
  }

  @Test func mixedUnsupportedRequestDeclinesWholeWithoutPartialExecution() async throws {
    let fixture = try LanguageFixture()
    defer { fixture.remove() }
    try fixture.write("a.txt")
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let request = "Sort by type and delete duplicates"
    let outcome = try await coordinator.planTask(
      request: request,
      model: { _, _, _ in
        Issue.record("A known unsupported action cannot be dropped by inference")
        return "{}"
      })
    guard case .unsupported(let reason) = outcome else {
      Issue.record("Must decline whole mixed request")
      return
    }
    #expect(reason.contains("Resubmit"))
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
    let request = "Rename files replacing spaces with hyphens"
    let response = try metadataResponse(
      request: request, sort: "none", rename: [separatorRule(evidence: request)],
      decisions: ["apply", "apply", "abstain"])
    let outcome = try await coordinator.planTask(request: request, model: { _, _, _ in response })
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
    let request = "Please organize my files by type"
    let response = try metadataResponse(request: request)
    let outcome = try await coordinator.planTask(request: request, model: { _, _, _ in response })
    guard case .plan(let plan) = outcome else {
      Issue.record("Expected complete plan")
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

func metadataResponse(
  request: String, status: String = "plan", sort: String = "type", value: String = "",
  rename: [[String: String]] = [], decisions: [String] = ["apply"], message: String = "",
  selection: [String: Any]? = nil, clauses: [[String: String]]? = nil
) throws -> String {
  let object: [String: Any] = [
    "status": status, "message": message,
    "clauses": clauses ?? [
      [
        "text": request,
        "effect": status == "clarification"
          ? "ambiguous"
          : status == "unsupported" ? "unsupported" : sort == "none" ? "rename" : "sort",
      ]
    ],
    "sort": ["kind": sort, "evidence": sort == "none" ? "" : request, "value": value],
    "rename": rename,
    "selection": selection ?? ["extensions": [String](), "nameContains": "", "evidence": ""],
    "files": decisions.enumerated().map {
      ["sourceID": "f\($0.offset)", "disposition": $0.element]
    },
  ]
  return String(
    decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
    as: UTF8.self)
}

func separatorRule(evidence: String, from: String = " ", to: String = "-") -> [String: String] {
  ["kind": "separator", "evidence": evidence, "value": to, "from": from]
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
