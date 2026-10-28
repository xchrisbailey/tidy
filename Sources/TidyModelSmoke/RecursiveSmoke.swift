import Foundation
import TidyCore
import TidyModel
import TidyModelRuntime

extension ModelSmoke {
  static func recursiveTaskSmoke(_ runtime: MLXLocalModelRuntime) async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "tidy-recursive-smoke-\(UUID())")
    let folder = root.appendingPathComponent("Selected")
    defer { try? FileManager.default.removeItem(at: root) }
    for directory in ["A/deep", "B", "Documents", "B/.hidden"] {
      try FileManager.default.createDirectory(
        at: folder.appendingPathComponent(directory), withIntermediateDirectories: true)
    }
    let names = [
      "A/deep/report.txt", "B/report.txt", "Documents/report.txt", "B/.hidden/secret.txt",
    ]
    for name in names {
      try Data("synthetic fixture \(name)".utf8).write(to: folder.appendingPathComponent(name))
    }
    let data = try folder.bookmarkData(
      options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    var stale = false
    let granted = try URL(
      resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI, .withoutMounting],
      relativeTo: nil, bookmarkDataIsStale: &stale)
    guard !stale else { throw LocalInferenceError.smokeCheckFailed }
    let bookmark = root.appendingPathComponent("settings/folder.bookmark")
    let coordinator = TaskCoordinator(bookmarkFile: bookmark)
    _ = try await coordinator.selectFolderForWriting(granted)
    let start = ContinuousClock.now
    let outcome = try await coordinator.planTask(
      request: "Please sort files by type including subfolders"
    ) { system, user, limit in
      try await runtime.completeJSON(system: system, user: user, maximumOutputTokens: limit)
    }
    guard case .plan(let plan) = outcome,
      plan.changedCount == 2, plan.moveCount == 2, plan.renameCount == 2,
      plan.unchanged.count == 1, plan.skipped.count == 1
    else { throw LocalInferenceError.smokeCheckFailed }
    let result = try await coordinator.execute(plan)
    guard result.changed.count == 2,
      FileManager.default.fileExists(atPath: folder.appendingPathComponent("A/deep").path),
      FileManager.default.fileExists(
        atPath: folder.appendingPathComponent("Documents/report (2).txt").path),
      FileManager.default.fileExists(
        atPath: folder.appendingPathComponent("Documents/report (3).txt").path)
    else { throw LocalInferenceError.smokeCheckFailed }
    try await TaskCoordinator(bookmarkFile: bookmark).undoTask(plan.id)
    for name in names {
      guard
        try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
          == "synthetic fixture \(name)"
      else {
        throw LocalInferenceError.smokeCheckFailed
      }
    }
    print(
      "Real-model recursive type sort passed: collisions, hidden subtree, folder preservation and reopened undo verified; seconds: \(start.duration(to: .now))"
    )
    await reportMetrics(runtime)
  }
}
