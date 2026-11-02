import Darwin
import Foundation
import Testing
import TidyCore

struct MutationSafetyTests {
  @Test(arguments: ["root", "destination"])
  func undoRejectsNanosecondBirthTimeDriftWithoutChangingFiles(folder: String) async throws {
    let fixture = try LanguageFixture()
    defer { fixture.remove() }
    try fixture.write("Report.txt")
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let plan = try await coordinator.planSortByType(request: "Sort by type")
    let result = try await coordinator.execute(plan)
    let operation = try #require(result.changed.first)
    let journal = fixture.bookmark.deletingLastPathComponent().appendingPathComponent(
      "operations.json")
    let durable = try Data(contentsOf: journal)
    let target =
      folder == "root" ? fixture.folder : fixture.folder.appendingPathComponent("Documents")
    var before = stat()
    try #require(lstat(target.path, &before) == 0)
    var changed = before.st_birthtimespec
    changed.tv_nsec += changed.tv_nsec < 999_999_926 ? 74 : -74
    var attributes = attrlist()
    attributes.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
    attributes.commonattr = attrgroup_t(ATTR_CMN_CRTIME)
    // Reproduce the observed metadata-only drift exactly, without replacing the directory
    // or relying on a host's background metadata writer to run during the test.
    try #require(
      setattrlist(
        target.path, &attributes, &changed, MemoryLayout<timespec>.size, UInt32(FSOPT_NOFOLLOW))
        == 0)
    var after = stat()
    try #require(lstat(target.path, &after) == 0)
    try #require(after.st_dev == before.st_dev && after.st_ino == before.st_ino)
    try #require(after.st_birthtimespec.tv_sec == before.st_birthtimespec.tv_sec)
    try #require(after.st_birthtimespec.tv_nsec == changed.tv_nsec)
    for report in [try await coordinator.recoveryReport(), try await coordinator.recoveryReport()] {
      #expect(report.count == 1 && report.first?.status == .uncertain)
    }
    let refusal: SortError = folder == "root" ? .writeGrantRequired : .uncertainIdentity
    await #expect(throws: refusal) { try await coordinator.undoTask(plan.id) }
    await #expect(throws: refusal) {
      try await coordinator.undoFile(operation.id)
    }
    #expect(try Data(contentsOf: journal) == durable)
    #expect(
      try Data(contentsOf: fixture.folder.appendingPathComponent("Documents/Report.txt"))
        == Data("fixture".utf8))
    #expect(
      !FileManager.default.fileExists(
        atPath: fixture.folder.appendingPathComponent("Report.txt").path))
    #expect(
      FileManager.default.fileExists(
        atPath: fixture.folder.appendingPathComponent("Documents").path))
  }

  @Test func undoCleanupDoesNotRemoveFoldersAfterRootReplacement() async throws {
    let fixture = try LanguageFixture()
    defer { fixture.remove() }
    try fixture.write("Report.txt")
    let detached = fixture.root.appendingPathComponent("Detached")
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark) { point in
      if point == .undoCompletionSaved {
        try FileManager.default.moveItem(at: fixture.folder, to: detached)
        try FileManager.default.createDirectory(
          at: fixture.folder, withIntermediateDirectories: false)
      }
    }
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let plan = try await coordinator.planSortByType(request: "Sort by type")
    _ = try await coordinator.execute(plan)
    try await coordinator.undoTask(plan.id)
    #expect(
      try Data(contentsOf: detached.appendingPathComponent("Report.txt")) == Data("fixture".utf8))
    #expect(
      FileManager.default.fileExists(atPath: detached.appendingPathComponent("Documents").path))
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.folder.path).isEmpty)
  }

  @Test(arguments: [false, true])
  func undoRejectsRootReplacementAtFinalBoundary(fileOnly: Bool) async throws {
    let fixture = try LanguageFixture()
    defer { fixture.remove() }
    try fixture.write("Report.txt")
    let detached = fixture.root.appendingPathComponent("Detached")
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark) { point in
      if point == .undoIntentSaved {
        try FileManager.default.moveItem(at: fixture.folder, to: detached)
        try FileManager.default.createDirectory(
          at: fixture.folder, withIntermediateDirectories: false)
        try Data("unrelated".utf8).write(to: fixture.folder.appendingPathComponent("Report.txt"))
      }
    }
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let plan = try await coordinator.planSortByType(request: "Sort by type")
    let result = try await coordinator.execute(plan)
    let operation = try #require(result.changed.first)
    await #expect(throws: SortError.uncertainIdentity) {
      if fileOnly {
        try await coordinator.undoFile(operation.id)
      } else {
        try await coordinator.undoTask(plan.id)
      }
    }
    #expect(
      try Data(contentsOf: detached.appendingPathComponent("Documents/Report.txt"))
        == Data("fixture".utf8))
    #expect(
      !FileManager.default.fileExists(atPath: detached.appendingPathComponent("Report.txt").path))
    #expect(
      try Data(contentsOf: fixture.folder.appendingPathComponent("Report.txt"))
        == Data("unrelated".utf8))
    #expect(try await coordinator.undoHistory().first?.state != .undone)
  }

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
