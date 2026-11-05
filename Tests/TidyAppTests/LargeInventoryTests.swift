import Foundation
import Testing
import TidyCore
@testable import TidyApp

@MainActor
@Suite(
  .serialized,
  .enabled(if: ProcessInfo.processInfo.environment["TIDY_LARGE_INVENTORY_TESTS"] == "1"))
struct LargeInventoryTests {
  @Test func largeInventoryKeepsWorkspaceResponsiveAndRefusesOversizedTask() async throws {
    let fixture = try LargeInventoryFixture()
    defer { fixture.remove() }
    let model = WorkspaceModel(
      coordinator: TaskCoordinator(bookmarkFile: fixture.bookmark),
      modelIsReady: { true },
      completion: { _, _, _ in
        Issue.record("The oversized task must be refused before model inference")
        throw PlanningError.invalidResponse
      })
    model.windowDidOpen()
    let heartbeat = InventoryHeartbeat()
    let timer = heartbeat.start()
    defer { timer.cancel() }
    let started = ContinuousClock.now
    model.inspect(fixture.folder, forWriting: true)
    #expect(model.phase == .inspecting && model.canCancel && !model.canSubmit)
    await model.waitUntilFinished()
    let elapsed = started.duration(to: .now)
    timer.cancel()
    await timer.value
    #expect(model.inventory?.candidateFiles.count == fixture.count)
    #expect(model.inventory?.skippedItems.count == 2)
    #expect(heartbeat.ticks > 2)
    #expect(model.canSubmit && !model.isBusy)
    model.submit()
    await model.waitUntilFinished()
    #expect(model.feedback?.kind == .failure)
    #expect(model.feedback?.detail == SortError.scopeTooLarge.localizedDescription)
    #expect(model.result == nil)
    #expect(try await model.coordinator.undoHistory().isEmpty)
    try fixture.verify()
    print(
      "INVENTORY completed entries=\(fixture.count + 2) elapsed=\(elapsed) "
        + "heartbeatTicks=\(heartbeat.ticks) maximumMainActorGap=\(heartbeat.maximumGap); "
        + "oversized task refused, bytes/history unchanged; not native UI evidence")
  }

  @Test func cancellingLargeRefreshDoesNotMutateOrAuthorizeStaleInventory() async throws {
    let fixture = try LargeInventoryFixture()
    defer { fixture.remove() }
    let model = WorkspaceModel(
      coordinator: TaskCoordinator(bookmarkFile: fixture.bookmark),
      modelIsReady: { true },
      completion: { _, _, _ in
        Issue.record("Inventory cancellation must not invoke the model")
        throw PlanningError.invalidResponse
      })
    model.windowDidOpen()
    model.inspect(fixture.folder, forWriting: true)
    await model.waitUntilFinished()
    let before = try Data(contentsOf: fixture.bookmark)
    model.request = "Sort by type"
    model.inspect()
    try await Task.sleep(for: .milliseconds(10))
    try #require(model.phase == .inspecting)
    let started = ContinuousClock.now
    model.cancel()
    #expect(model.phase == .cancelling && !model.canSubmit)
    await model.waitUntilFinished()
    let elapsed = started.duration(to: .now)
    #expect(model.feedback?.kind == .cancelled)
    #expect(model.phase == .idle && !model.isBusy)
    #expect(model.inventory == nil && !model.canSubmit)
    #expect(model.request == "Sort by type")
    #expect(try Data(contentsOf: fixture.bookmark) == before)
    #expect(try await model.coordinator.undoHistory().isEmpty)
    model.inspect()
    await model.waitUntilFinished()
    #expect(model.inventory?.candidateFiles.count == fixture.count && model.canSubmit)
    try fixture.verify()
    print(
      "INVENTORY refresh cancelled after 10ms while inspecting; drained=\(elapsed); "
        + "request/bookmark preserved, stale submission blocked, later refresh passed; "
        + "local metadata only")
  }
}

@MainActor private final class InventoryHeartbeat {
  var ticks = 0
  var maximumGap = Duration.zero

  func start() -> Task<Void, Never> {
    Task {
      var last = ContinuousClock.now
      while !Task.isCancelled {
        do { try await Task.sleep(for: .milliseconds(5)) } catch { break }
        let now = ContinuousClock.now
        maximumGap = max(maximumGap, last.duration(to: now))
        ticks += 1
        last = now
      }
    }
  }
}

private struct LargeInventoryFixture {
  let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
    .appendingPathComponent("tidy-large-inventory-\(UUID())")
  let count = 10_000
  let bytes = Data("Only synthetic inventory control.\n".utf8)
  var folder: URL { root.appendingPathComponent("Selected") }
  var bookmark: URL { root.appendingPathComponent("settings/folder.bookmark") }

  init() throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for index in 0..<count {
      try bytes.write(to: folder.appendingPathComponent("item-\(index).txt"))
    }
    try bytes.write(to: folder.appendingPathComponent(".hidden-control"))
    let nested = folder.appendingPathComponent("Existing")
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
    try bytes.write(to: nested.appendingPathComponent("nested-control.txt"))
  }

  func verify() throws {
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == count + 2)
    for index in 0..<count {
      #expect(try Data(contentsOf: folder.appendingPathComponent("item-\(index).txt")) == bytes)
    }
    #expect(try Data(contentsOf: folder.appendingPathComponent(".hidden-control")) == bytes)
    #expect(
      try Data(contentsOf: folder.appendingPathComponent("Existing/nested-control.txt")) == bytes)
    #expect(
      !FileManager.default.fileExists(atPath: folder.appendingPathComponent("Documents").path))
  }

  func remove() { try? FileManager.default.removeItem(at: root) }
}
