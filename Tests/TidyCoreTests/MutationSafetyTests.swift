import Foundation
import Testing
import TidyCore

struct MutationSafetyTests {
  @Test(arguments: ["single", "batch"])
  func sharedMutationEngineRejectsRootReplacementAtFinalBoundary(entryPoint: String) async throws {
    let fixture = try LanguageFixture()
    defer { fixture.remove() }
    try fixture.write("Report.txt")
    let detached = fixture.root.appendingPathComponent("Detached")
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark) { point in
      if point == .beforeMove {
        try FileManager.default.moveItem(at: fixture.folder, to: detached)
        try FileManager.default.createDirectory(
          at: fixture.folder, withIntermediateDirectories: false)
        try Data("unrelated".utf8).write(to: fixture.folder.appendingPathComponent("Report.txt"))
      }
    }
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    if entryPoint == "single" {
      await #expect(throws: SortError.uncertainIdentity) {
        try await coordinator.sortByType(request: "Sort by type")
      }
    } else {
      let plan = try await coordinator.planSortByType(request: "Sort by type")
      let result = try await coordinator.execute(plan)
      #expect(result.changed.isEmpty)
      #expect(result.failed.count == 1)
    }
    #expect(
      try Data(contentsOf: detached.appendingPathComponent("Report.txt")) == Data("fixture".utf8))
    #expect(
      try Data(contentsOf: fixture.folder.appendingPathComponent("Report.txt"))
        == Data("unrelated".utf8))
    #expect(
      !FileManager.default.fileExists(
        atPath: detached.appendingPathComponent("Documents/Report.txt").path))
  }
}
