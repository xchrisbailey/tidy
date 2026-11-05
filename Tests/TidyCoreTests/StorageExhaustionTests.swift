import Darwin
import Foundation
import Testing
import TidyCore

@Suite(.serialized)
struct StorageExhaustionTests {
  @Test(
    .enabled(if: ProcessInfo.processInfo.environment["TIDY_DISPOSABLE_VOLUME"] != nil),
    arguments: ["execute", "undo"])
  func exhaustedJournalVolumePreservesFilesAndDurableHistory(phase: String) async throws {
    let mount = URL(
      fileURLWithPath: try #require(ProcessInfo.processInfo.environment["TIDY_DISPOSABLE_VOLUME"])
    ).resolvingSymlinksInPath()
    var volume = statfs()
    try #require(statfs(mount.path, &volume) == 0)
    let mountedPath = withUnsafePointer(to: &volume.f_mntonname) {
      $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
    }
    let capacity = volume.f_blocks * UInt64(volume.f_bsize)
    // Exhaust only an explicitly opted-in, small mounted test volume, never the
    // host filesystem or a subdirectory that merely looks like a mount point.
    try #require(URL(fileURLWithPath: mountedPath).resolvingSymlinksInPath() == mount)
    try #require(capacity > 0 && capacity <= 300 * 1024 * 1024)
    var host = statfs()
    try #require(statfs("/", &host) == 0)
    try #require(volume.f_fsid.val.0 != host.f_fsid.val.0)
    let root = mount.appendingPathComponent("tidy-full-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("Selected")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    let source = folder.appendingPathComponent("notes.txt")
    let bytes = Data("Disposable disk-full journal fixture.\n".utf8)
    try bytes.write(to: source)
    let bookmark = root.appendingPathComponent("settings/folder.bookmark")
    let coordinator = TaskCoordinator(bookmarkFile: bookmark)
    _ = try await coordinator.selectFolderForWriting(folder)
    print("DISK-FULL selected owned folder")
    let first = try await coordinator.sortByType(request: "Sort by type")
    print("DISK-FULL initial move completed")
    if phase == "execute" { try await coordinator.undoTask(first.id) }
    let journal = bookmark.deletingLastPathComponent().appendingPathComponent("operations.json")
    let durable = try Data(contentsOf: journal)
    _ = try await coordinator.restoreFolder()
    let plan = try await coordinator.planSortByType(request: "Sort by type")
    let filler = root.appendingPathComponent("owned-capacity-filler")
    var fd = open(filler.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
    try #require(fd >= 0)
    defer { if fd >= 0 { close(fd) } }
    defer { try? FileManager.default.removeItem(at: filler) }
    let block = [UInt8](repeating: 0xa5, count: 1024 * 1024)
    var written = 0
    var failure: Int32 = 0
    for size in [block.count, 4096, 1] {
      while written <= 300 * 1024 * 1024 {
        let count = block.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, size) }
        if count < 0 {
          failure = errno
          break
        }
        try #require(count > 0)
        written += count
      }
      try #require(failure == ENOSPC)
    }
    try #require(failure == ENOSPC)
    print("DISK-FULL reached ENOSPC after \(written) bytes")
    var journalRefused = false
    if phase == "execute" {
      do {
        let result = try await coordinator.execute(plan)
        #expect(result.changed.count + result.failed.count == 1)
        #expect(result.unprocessed.isEmpty)
        journalRefused =
          result.changed.isEmpty
          && result.failureExplanation == SortError.journalUnavailable.localizedDescription
      } catch {
        #expect(error as? SortError == .journalUnavailable)
        journalRefused = true
      }
    } else {
      do {
        try await coordinator.undoTask(first.id)
      } catch {
        #expect(error as? SortError == .journalUnavailable)
        journalRefused = true
      }
    }
    let destination = folder.appendingPathComponent("Documents/notes.txt")
    let atOriginal = FileManager.default.fileExists(atPath: source.path)
    #expect(atOriginal != FileManager.default.fileExists(atPath: destination.path))
    let current = atOriginal ? source : destination
    #expect(try Data(contentsOf: current) == bytes)
    if journalRefused { #expect(try Data(contentsOf: journal) == durable) }
    close(fd)
    fd = -1
    try FileManager.default.removeItem(at: filler)
    let reopened = TaskCoordinator(bookmarkFile: bookmark)
    _ = try await reopened.restoreFolder()
    let report = try await reopened.recoveryReport()
    // A successful second move can make an older undone record's paths uncertain.
    // Require recovery of the newest operation, not rewritten historical identity.
    #expect(report.last?.status != .uncertain)
    #expect(report.contains { $0.id == first.id })
    if !atOriginal {
      #expect(report.contains { $0.status == .completed })
      try await reopened.undoTask(phase == "execute" ? plan.id : first.id)
    }
    #expect(try Data(contentsOf: source) == bytes)
    _ = try await reopened.restoreFolder()
    let retry = try await reopened.sortByType(request: "Sort by type")
    try await reopened.undoTask(retry.id)
    #expect(try Data(contentsOf: source) == bytes)
    print(
      "PASS real ENOSPC \(phase): journalRefused=\(journalRefused), atOriginal=\(atOriginal); original bytes, durable recovery and fresh retry/undo passed"
    )
  }
}
