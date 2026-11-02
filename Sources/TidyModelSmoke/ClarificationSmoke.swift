import Foundation
import TidyCore
import TidyModelRuntime

extension ModelSmoke {
  @MainActor static func clarificationSmoke(_ runtime: MLXLocalModelRuntime) async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let folder = root.appendingPathComponent("Files")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let bytes = Data("Only synthetic clarification notes.\n".utf8)
    for name in ["notes.txt", "report.txt"] {
      try bytes.write(to: folder.appendingPathComponent(name))
    }
    let bookmark = root.appendingPathComponent("bookmark")
    let coordinator = TaskCoordinator(bookmarkFile: bookmark)
    let data = try folder.bookmarkData(
      options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    var stale = false
    let granted = try URL(
      resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI, .withoutMounting],
      relativeTo: nil, bookmarkDataIsStale: &stale)
    _ = try await coordinator.selectFolderForWriting(granted)
    var failures = 0
    for request in [
      "Organize these files", "Sort only notes.txt by type", "Rename these files",
      "Please organize my files", "Rename all files", "Sort only report.txt by type",
    ] {
      do {
        let outcome = try await coordinator.planTask(request: request) { system, user, limit in
          try await runtime.completeJSON(
            system: system, user: user, maximumOutputTokens: limit)
        }
        guard case .clarification(let question) = outcome else {
          throw LocalInferenceError.smokeCheckFailed
        }
        guard !question.isEmpty else { throw LocalInferenceError.smokeCheckFailed }
        print("PASS clarification: \(request); \(question)")
      } catch {
        print("FAIL clarification: \(request); \(error)")
        failures += 1
      }
      for name in ["notes.txt", "report.txt"] {
        guard try Data(contentsOf: folder.appendingPathComponent(name)) == bytes else {
          throw LocalInferenceError.smokeCheckFailed
        }
      }
      guard
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
          == ["notes.txt", "report.txt"]
      else { throw LocalInferenceError.smokeCheckFailed }
    }
    guard failures == 0 else { throw LocalInferenceError.smokeCheckFailed }
    let explicit = try await coordinator.planTask(request: "Sort by type") { system, user, limit in
      try await runtime.completeJSON(system: system, user: user, maximumOutputTokens: limit)
    }
    guard case .plan(let plan) = explicit, plan.moveCount == 2, plan.renameCount == 0 else {
      throw LocalInferenceError.smokeCheckFailed
    }
    guard try await coordinator.execute(plan).changed.count == 2 else {
      throw LocalInferenceError.smokeCheckFailed
    }
    try await TaskCoordinator(bookmarkFile: bookmark).undoTask(plan.id)
    _ = try await coordinator.restoreFolder()
    let refused = try await coordinator.planTask(request: "Sort by type and delete duplicates") {
      system, user, limit in
      try await runtime.completeJSON(system: system, user: user, maximumOutputTokens: limit)
    }
    guard case .unsupported = refused else { throw LocalInferenceError.smokeCheckFailed }
    for name in ["notes.txt", "report.txt"] {
      guard try Data(contentsOf: folder.appendingPathComponent(name)) == bytes else {
        throw LocalInferenceError.smokeCheckFailed
      }
    }
    guard
      try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        == ["notes.txt", "report.txt"]
    else { throw LocalInferenceError.smokeCheckFailed }
    print(
      "PASS clarification resubmission: two moves, reopened undo, mixed deletion refusal; original paths/bytes restored"
    )
  }
}
