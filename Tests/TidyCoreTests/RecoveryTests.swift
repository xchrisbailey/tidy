import Foundation
import Testing
import TidyCore

struct RecoveryTests {
  @Test func historyRemainsAvailableDuringIndependentProcessLaunches() async throws {
    let fixture = try RecoveryFixture()
    defer { fixture.remove() }
    try Data("keep".utf8).write(to: fixture.source)
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let operation = try await coordinator.sortByType(request: "Sort by type")
    try await withThrowingTaskGroup(of: Void.self) { group in
      for _ in 0..<4 {
        group.addTask {
          for _ in 0..<50 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
            try process.run()
            process.waitUntilExit()
          }
        }
      }
      group.addTask { () async throws -> Void in
        for _ in 0..<2_000 {
          #expect(try await coordinator.undoHistory().first?.id == operation.id)
        }
      }
      try await group.waitForAll()
    }
    try await TaskCoordinator(bookmarkFile: fixture.bookmark).undoTask(operation.id)
    #expect(try Data(contentsOf: fixture.source) == Data("keep".utf8))
  }

  @Test func rejectedCompetingHistoryReadsDoNotDisturbIndependentRecovery() async throws {
    let fixture = try RecoveryFixture()
    defer { fixture.remove() }
    try Data("keep".utf8).write(to: fixture.source)
    let owner = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await owner.selectFolderForWriting(fixture.folder)
    let plan = try await owner.planSortByType(request: "Sort by type")
    var readerFixtures: [RecoveryFixture] = []
    defer { for readerFixture in readerFixtures { readerFixture.remove() } }
    var preparedReaders: [(TaskCoordinator, UUID, URL)] = []
    for _ in 0..<2 {
      let readerFixture = try RecoveryFixture()
      readerFixtures.append(readerFixture)
      let reader = TaskCoordinator(bookmarkFile: readerFixture.bookmark)
      try Data("keep".utf8).write(to: readerFixture.source)
      _ = try await reader.selectFolderForWriting(readerFixture.folder)
      let operation = try await reader.sortByType(request: "Sort by type")
      preparedReaders.append((reader, operation.id, readerFixture.source))
    }
    let readers = preparedReaders
    let entered = AsyncStream<Void>.makeStream()
    let release = AsyncStream<Void>.makeStream()
    let execution = Task {
      defer { entered.continuation.finish() }
      return try await owner.execute(plan) { progress in
        if progress.processed == 0 {
          entered.continuation.yield(())
          for await _ in release.stream { break }
        }
      }
    }
    var entry = entered.stream.makeAsyncIterator()
    guard await entry.next() != nil else {
      _ = try await execution.value
      Issue.record("Execution finished before the lock-holding callback")
      return
    }
    let competing = TaskCoordinator(bookmarkFile: fixture.bookmark)
    let rejected = Task {
      var count = 0
      while !Task.isCancelled {
        do {
          _ = try await competing.undoHistory()
          Issue.record("A competing coordinator acquired the active task's journal")
          break
        } catch SortError.busy { count += 1 }
        await Task.yield()
      }
      return count
    }
    var failure: (any Error)?
    do {
      try await withThrowingTaskGroup(of: Void.self) { group in
        for (reader, operationID, _) in readers {
          group.addTask {
            do {
              for _ in 0..<500 {
                try Task.checkCancellation()
                #expect(try await reader.undoHistory().first?.id == operationID)
              }
            } catch let error as SortError {
              Issue.record("Independent reopened-history read failed with code: \(error)")
              throw error
            }
          }
        }
        for _ in 0..<4 {
          group.addTask {
            for _ in 0..<6 {
              try Task.checkCancellation()
              try await Self.exerciseNewerTaskConflict()
            }
          }
        }
        try await group.waitForAll()
      }
    } catch { failure = error }
    rejected.cancel()
    do { #expect(try await rejected.value > 0) } catch { if failure == nil { failure = error } }
    release.continuation.yield(())
    release.continuation.finish()
    #expect(try await execution.value.changed.count == 1)
    try await TaskCoordinator(bookmarkFile: fixture.bookmark).undoTask(plan.id)
    #expect(try Data(contentsOf: fixture.source) == Data("keep".utf8))
    for (reader, operationID, source) in readers {
      try await reader.undoTask(operationID)
      #expect(try Data(contentsOf: source) == Data("keep".utf8))
    }
    if let failure { throw failure }
  }

  @Test func newerTaskConflictDoesNotPreventOtherSafeFilesInPartialTaskUndo() async throws {
    try await Self.exerciseNewerTaskConflict()
  }

  private static func exerciseNewerTaskConflict() async throws {
    let fixture = try RecoveryFixture()
    defer { fixture.remove() }
    var phase = "create fixture files"
    do {
      try Data("keep".utf8).write(to: fixture.source)
      let other = fixture.folder.appendingPathComponent("other.txt")
      try Data("other".utf8).write(to: other)
      let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
      phase = "select initial folder"
      _ = try await coordinator.selectFolderForWriting(fixture.folder)
      phase = "plan initial task"
      let plan = try await coordinator.planSortByType(request: "Sort by type")
      phase = "execute initial task"
      _ = try await coordinator.execute(plan)
      phase = "external reposition"
      try FileManager.default.moveItem(at: fixture.sorted, to: fixture.source)
      phase = "select repositioned folder"
      _ = try await coordinator.selectFolderForWriting(fixture.folder)
      phase = "execute newer task"
      let newer = try await coordinator.sortByType(request: "Sort by type")
      let reopened = TaskCoordinator(bookmarkFile: fixture.bookmark)
      phase = "undo older task"
      do {
        try await reopened.undoTask(plan.id)
        Issue.record("Older undo must report the newer-operation conflict")
      } catch SortError.newerOperation {}
      phase = "verify preserved contents"
      #expect(try Data(contentsOf: other) == Data("other".utf8))
      #expect(try Data(contentsOf: fixture.sorted) == Data("keep".utf8))
      phase = "first reopened history read"
      #expect(try await reopened.undoHistory().last?.id == newer.id)
      phase = "second reopened history read"
      #expect(try await reopened.undoHistory().last?.state == .completed)
    } catch let error as SortError {
      Issue.record("Recovery conflict scenario failed at phase: \(phase); code: \(error)")
      throw error
    } catch {
      Issue.record(
        "Recovery conflict scenario failed at phase: \(phase); error type: \(type(of: error))")
      throw error
    }
  }

  @Test func changedLocationsDoNotOfferUndoForATerminalRecord() async throws {
    let fixture = try RecoveryFixture()
    defer { fixture.remove() }
    try FileManager.default.createDirectory(
      at: fixture.sorted.deletingLastPathComponent(), withIntermediateDirectories: false)
    try Data("keep".utf8).write(to: fixture.source)
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let entry = try await coordinator.sortByType(request: "Sort by type")
    try await coordinator.undoFile(entry.id)
    try FileManager.default.moveItem(at: fixture.source, to: fixture.sorted)
    let report = try #require(try await coordinator.recoveryReport().first)
    #expect(report.status == .uncertain)
    #expect(!report.options.contains(.undoFile))
    #expect(try await coordinator.undoHistory().first?.state == .undone)
  }

  @Test func reconciliationResolvesNewerUnappliedIntentsBeforeOlderOnesInOnePass() async throws {
    let fixture = try RecoveryFixture()
    defer { fixture.remove() }
    try Data("keep".utf8).write(to: fixture.source)
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let older = try await coordinator.sortByType(request: "Sort by type")
    try FileManager.default.moveItem(at: fixture.sorted, to: fixture.source)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let newer = try await coordinator.sortByType(request: "Sort by type")
    try FileManager.default.moveItem(at: fixture.sorted, to: fixture.source)
    var objects = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode([older, newer])) as? [[String: Any]])
    for index in objects.indices { objects[index]["state"] = "intent" }
    try JSONSerialization.data(withJSONObject: objects).write(to: fixture.journal)
    let reopened = TaskCoordinator(bookmarkFile: fixture.bookmark)
    let first = try await reopened.recoveryReport()
    #expect(first.map(\.status) == [.unapplied, .unapplied])
    let bytes = try Data(contentsOf: fixture.journal)
    #expect(try await reopened.recoveryReport().map(\.status) == first.map(\.status))
    #expect(try Data(contentsOf: fixture.journal) == bytes)
  }

  @Test(arguments: [OperationCheckpoint.afterMove, .afterUndoMove])
  func actualJournalSaveFailureAfterMutationRetainsRecoverableIntent(
    checkpoint: OperationCheckpoint
  ) async throws {
    let fixture = try RecoveryFixture()
    defer { fixture.remove() }
    let settings = fixture.bookmark.deletingLastPathComponent()
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o700], ofItemAtPath: settings.path)
    }
    try Data("keep".utf8).write(to: fixture.source)
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark) { point in
      if point == checkpoint {
        try FileManager.default.setAttributes(
          [.posixPermissions: 0o500], ofItemAtPath: settings.path)
      }
    }
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let plan = try await coordinator.planSortByType(request: "Sort by type")
    let result = try await coordinator.execute(plan)
    if checkpoint == .afterMove {
      #expect(result.isPartial)
      #expect(result.changed.count == 1)
      #expect(result.failed.isEmpty)
    } else {
      let handle = try FileHandle(forWritingTo: fixture.sorted)
      try handle.truncate(atOffset: 0)
      try handle.write(contentsOf: Data("edited later".utf8))
      try handle.close()
      await #expect(throws: SortError.journalUnavailable) {
        try await coordinator.undoTask(plan.id)
      }
    }
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: settings.path)
    let reopened = TaskCoordinator(bookmarkFile: fixture.bookmark)
    let durable = try #require(try await reopened.historySnapshot().operations.first)
    #expect(durable.state == (checkpoint == .afterMove ? .intent : .undoIntent))
    let expected: RecoveryStatus = checkpoint == .afterMove ? .completed : .undone
    #expect(try await reopened.recoveryReport().first?.status == expected)
    #expect(try await reopened.recoveryReport().first?.status == expected)
    if checkpoint == .afterMove {
      try await reopened.undoTask(plan.id)
      #expect(try Data(contentsOf: fixture.source) == Data("keep".utf8))
    } else {
      #expect(try Data(contentsOf: fixture.source) == Data("edited later".utf8))
      #expect(
        FileManager.default.fileExists(atPath: fixture.sorted.deletingLastPathComponent().path))
      try await reopened.undoFile(durable.id)
      #expect(
        !FileManager.default.fileExists(atPath: fixture.sorted.deletingLastPathComponent().path))
    }
  }

  @Test(arguments: [OperationCheckpoint.beforeMove, .afterMove, .folderCreated])
  func interruptedBatchReopensIdempotentlyWithoutResuming(checkpoint: OperationCheckpoint)
    async throws
  {
    let fixture = try RecoveryFixture()
    defer { fixture.remove() }
    try Data("keep".utf8).write(to: fixture.source)
    try Data("later".utf8).write(to: fixture.folder.appendingPathComponent("z.txt"))
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark) { point in
      if point == checkpoint { throw SortError.unavailable }
    }
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let plan = try await coordinator.planSortByType(request: "Sort by type")
    let result = try await coordinator.execute(plan)
    #expect(result.isPartial)
    #expect(result.unprocessed == ["z.txt"])
    let reopened = TaskCoordinator(bookmarkFile: fixture.bookmark)
    let report = try await reopened.recoveryReport()
    #expect(report.count == 1)
    let expected: RecoveryStatus =
      checkpoint == .afterMove
      ? .completed
      : checkpoint == .beforeMove ? .unapplied : .uncertain
    #expect(report.first?.status == expected)
    #expect(try await reopened.recoveryReport().first?.status == expected)
    #expect(
      try Data(contentsOf: fixture.folder.appendingPathComponent("z.txt")) == Data("later".utf8))
    #expect(
      FileManager.default.fileExists(atPath: fixture.source.path) == (checkpoint != .afterMove))
    #expect(FileManager.default.fileExists(atPath: fixture.sorted.deletingLastPathComponent().path))
    if checkpoint == .afterMove {
      try await reopened.undoTask(plan.id)
      #expect(try Data(contentsOf: fixture.source) == Data("keep".utf8))
    }
  }

  @Test func recoveryReportsActualStateWithoutTreatingIntentAsCompletion() async throws {
    let fixture = try RecoveryFixture()
    defer { fixture.remove() }
    try Data("keep".utf8).write(to: fixture.source)
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let entry = try await coordinator.sortByType(request: "Sort by type")
    try fixture.record(entry, state: "intent")
    let reopened = TaskCoordinator(bookmarkFile: fixture.bookmark)
    let completed = try #require(try await reopened.recoveryReport().first)
    #expect(completed.status == .completed)
    #expect(completed.options.contains(.undoFile))
    try FileManager.default.moveItem(at: fixture.sorted, to: fixture.source)
    try fixture.record(entry, state: "intent")
    let unapplied = try #require(try await reopened.recoveryReport().first)
    #expect(unapplied.status == .unapplied)
    #expect(!unapplied.options.contains(.undoFile))
    #expect(FileManager.default.fileExists(atPath: fixture.sorted.deletingLastPathComponent().path))
    try FileManager.default.removeItem(at: fixture.source)
    try fixture.record(entry, state: "intent")
    let uncertain = try #require(try await reopened.recoveryReport().first)
    #expect(uncertain.status == .uncertain)
    #expect(uncertain.options == [.inspect])
    #expect(try await reopened.undoHistory().first?.state == .intent)
    #expect(try await reopened.recoveryReport().first?.status == .uncertain)
  }

  @Test func olderUndoCannotSilentlyReverseANewerTaskForTheSameIdentity() async throws {
    let fixture = try RecoveryFixture()
    defer { fixture.remove() }
    try Data("keep".utf8).write(to: fixture.source)
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let older = try await coordinator.sortByType(request: "Sort by type")
    try FileManager.default.moveItem(at: fixture.sorted, to: fixture.source)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let newer = try await coordinator.sortByType(request: "Sort by type")
    let reopened = TaskCoordinator(bookmarkFile: fixture.bookmark)
    await #expect(throws: SortError.newerOperation) { try await reopened.undoFile(older.id) }
    await #expect(throws: SortError.newerOperation) { try await reopened.undoTask(older.taskID) }
    let report = try #require(try await reopened.recoveryReport().first)
    #expect(report.blockingTaskID == newer.taskID)
    #expect(!report.options.contains(.undoFile))
    #expect(try await reopened.undoHistory().last?.state == .completed)
    #expect(try Data(contentsOf: fixture.sorted) == Data("keep".utf8))
    try await reopened.undoTask(newer.taskID)
    #expect(try Data(contentsOf: fixture.source) == Data("keep".utf8))
  }

  @Test func reopeningDoesNotRemoveAnIdentifiedEmptyCreatedFolder() async throws {
    let fixture = try RecoveryFixture()
    defer { fixture.remove() }
    try Data("keep".utf8).write(to: fixture.source)
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await coordinator.selectFolderForWriting(fixture.folder)
    let entry = try await coordinator.sortByType(request: "Sort by type")
    try FileManager.default.moveItem(at: fixture.sorted, to: fixture.source)
    try fixture.record(entry, state: "undoIntent")
    let reopened = TaskCoordinator(bookmarkFile: fixture.bookmark)
    #expect(try await reopened.undoHistory().first?.state == .undone)
    #expect(FileManager.default.fileExists(atPath: fixture.sorted.deletingLastPathComponent().path))
    #expect(try await reopened.undoHistory().first?.state == .undone)
    try await reopened.undoFile(entry.id)
    #expect(
      !FileManager.default.fileExists(atPath: fixture.sorted.deletingLastPathComponent().path))
  }
}

private struct RecoveryFixture {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "tidy-recovery-\(UUID())")
  var folder: URL { root.appendingPathComponent("Selected") }
  var bookmark: URL { root.appendingPathComponent("settings/folder.bookmark") }
  var source: URL { folder.appendingPathComponent("notes.txt") }
  var sorted: URL { folder.appendingPathComponent("Documents/notes.txt") }
  var journal: URL {
    bookmark.deletingLastPathComponent().appendingPathComponent("operations.json")
  }

  init() throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  }

  func remove() { try? FileManager.default.removeItem(at: root) }

  func record(_ entry: FileOperation, state: String) throws {
    var object = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
    object["state"] = state
    try JSONSerialization.data(withJSONObject: [object]).write(
      to: bookmark.deletingLastPathComponent().appendingPathComponent("operations.json"))
  }
}
