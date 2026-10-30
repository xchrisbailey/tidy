import Foundation
import Testing
import TidyCore
import os

@testable import TidyApp

@MainActor
struct WorkspaceModelTests {
  @Test func navigationDoesNotCancelPlanningOrLoseItsResult() async throws {
    let fixture = try WorkspaceFixture(count: 2)
    defer { fixture.remove() }
    let gate = PlanningGate()
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    let model = WorkspaceModel(
      coordinator: coordinator, modelIsReady: { true },
      completion: { _, _, _ in
        await gate.complete()
      })
    model.windowDidOpen()
    model.inspect(fixture.folder, forWriting: true)
    await model.waitUntilFinished()
    model.submit()
    await gate.waitUntilStarted()
    model.destination = .history
    model.restoreIfNeeded()
    model.submit()
    #expect(model.phase == .planning)
    #expect(model.isBusy)
    #expect(await gate.calls == 1)
    await gate.release()
    await model.waitUntilFinished()
    #expect(model.destination == .history)
    #expect(model.result?.changed.count == 2)
    #expect(model.feedback?.kind == .success)
    #expect(model.history?.operations.count == 2)
    model.destination = .organize
    model.restoreIfNeeded()
    #expect(model.result?.changed.count == 2)
    #expect(!model.isBusy)
  }

  @Test(arguments: [false, true])
  func explicitCancellationOrWindowCloseRejectsLateInferenceOutput(closeWindow: Bool) async throws {
    let fixture = try WorkspaceFixture(count: 1)
    defer { fixture.remove() }
    let gate = PlanningGate()
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    let model = WorkspaceModel(
      coordinator: coordinator, modelIsReady: { true },
      completion: { _, _, _ in
        await gate.complete()
      })
    model.windowDidOpen()
    model.inspect(fixture.folder, forWriting: true)
    await model.waitUntilFinished()
    model.submit()
    await gate.waitUntilStarted()
    if closeWindow { model.closeWindow() } else { model.cancel() }
    #expect(model.phase == .cancelling)
    #expect(model.isBusy)
    await gate.release()
    await model.waitUntilFinished()
    #expect(model.feedback?.kind == .cancelled)
    #expect(!model.isBusy)
    #expect(try await coordinator.historySnapshot().operations.isEmpty)
    #expect(
      try FileManager.default.contentsOfDirectory(atPath: fixture.folder.path) == ["file-0.txt"])
  }

  @Test func readinessAndReadGrantCannotAuthorizeExecution() async throws {
    let fixture = try WorkspaceFixture(count: 1)
    defer { fixture.remove() }
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    let readiness = ReadinessFixture()
    let model = WorkspaceModel(
      coordinator: coordinator, modelIsReady: { readiness.ready },
      completion: {
        _, _, _ in
        Issue.record("No inference should run without readiness and write authority")
        return sortResponse
      })
    model.windowDidOpen()
    model.inspect(fixture.folder)
    await model.waitUntilFinished()
    #expect(!model.canSubmit)
    model.submit()
    await model.waitUntilFinished()
    #expect(model.feedback?.kind == .information)
    readiness.ready = true
    model.submit()
    await model.waitUntilFinished()
    #expect(model.feedback?.kind == .failure)
    #expect(model.result == nil)
    #expect(try await coordinator.historySnapshot().operations.isEmpty)
    #expect(
      FileManager.default.fileExists(
        atPath: fixture.folder.appendingPathComponent("file-0.txt").path))
  }

  @Test func largeTaskRetainsOneImmutablePlanUntilExplicitConfirmation() async throws {
    let fixture = try WorkspaceFixture(count: 101)
    defer { fixture.remove() }
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    let model = WorkspaceModel(
      coordinator: coordinator, modelIsReady: { true },
      completion: { _, _, _ in
        sortResponse
      })
    model.windowDidOpen()
    model.inspect(fixture.folder, forWriting: true)
    await model.waitUntilFinished()
    model.submit()
    await model.waitUntilFinished()
    let plan = try #require(model.pendingPlan)
    #expect(model.phase == .confirming)
    #expect(plan.changedCount == 101)
    model.inspect(fixture.root)
    model.submit()
    #expect(model.pendingPlan?.id == plan.id)
    #expect(try await coordinator.historySnapshot().operations.isEmpty)
    model.dismissPlan()
    #expect(model.pendingPlan == nil)
    #expect(!model.isBusy)
    model.submit()
    await model.waitUntilFinished()
    model.confirmPlan()
    await model.waitUntilFinished()
    #expect(model.result?.changed.count == 101)
    #expect(model.history?.operations.count == 101)
    #expect(!model.isBusy)
  }

  @Test func cancelledExecutionKeepsCompletedChangesAndRefreshesInventory() async throws {
    let fixture = try WorkspaceFixture(count: 2)
    defer { fixture.remove() }
    let gate = WorkspaceCheckpointGate()
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark) { point in
      if point == .completionSaved { gate.pauseOnce() }
    }
    let model = WorkspaceModel(
      coordinator: coordinator, modelIsReady: { true },
      completion: { _, _, _ in
        sortResponse
      })
    model.windowDidOpen()
    model.inspect(fixture.folder, forWriting: true)
    await model.waitUntilFinished()
    model.submit()
    await gate.waitUntilPaused()
    model.destination = .history
    #expect(model.phase == .executing)
    model.cancel()
    #expect(model.isBusy)
    gate.resume()
    await model.waitUntilFinished()
    #expect(model.result?.cancelled == true)
    #expect(model.result?.changed.count == 1)
    #expect(model.result?.unprocessed.count == 1)
    #expect(model.feedback?.kind == .cancelled)
    #expect(model.inventory?.candidateFiles.count == 1)
    #expect(model.history?.operations.count == 1)
    #expect(model.refreshError == nil)
  }

  @Test func navigationAndUndoCancellationPreserveDurableReversals() async throws {
    let fixture = try WorkspaceFixture(count: 2)
    defer { fixture.remove() }
    let gate = WorkspaceCheckpointGate()
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark) { point in
      if point == .undoCompletionSaved { gate.pauseOnce() }
    }
    let model = WorkspaceModel(
      coordinator: coordinator, modelIsReady: { true },
      completion: { _, _, _ in
        sortResponse
      })
    model.windowDidOpen()
    model.inspect(fixture.folder, forWriting: true)
    await model.waitUntilFinished()
    model.submit()
    await model.waitUntilFinished()
    let taskID = try #require(model.result?.taskID)
    model.undo(taskID, fileOnly: false)
    await gate.waitUntilPaused()
    model.destination = .organize
    #expect(model.undoActivity.isWorking)
    model.cancel()
    gate.resume()
    await model.waitUntilFinished()
    #expect(model.feedback?.kind == .cancelled)
    #expect(model.history?.operations.filter { $0.state == .undone }.count == 1)
    #expect(model.history?.operations.filter { $0.state == .completed }.count == 1)
    #expect(!model.isBusy)
  }

  @Test func refreshFailureCannotErasePartialMutationOutcomes() async throws {
    let fixture = try WorkspaceFixture(count: 2)
    defer { fixture.remove() }
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark) { point in
      if point == .completionSaved {
        try Data("corrupt bookmark".utf8).write(to: fixture.bookmark)
        throw WorkspaceFixtureError.interrupted
      }
    }
    let model = WorkspaceModel(
      coordinator: coordinator, modelIsReady: { true },
      completion: { _, _, _ in
        sortResponse
      })
    model.windowDidOpen()
    model.inspect(fixture.folder, forWriting: true)
    await model.waitUntilFinished()
    model.submit()
    await model.waitUntilFinished()
    #expect(model.result?.changed.count == 1)
    #expect(model.result?.isPartial == true)
    #expect(model.feedback?.kind == .failure)
    #expect(model.inventoryRefreshError != nil)
    #expect(model.history?.operations.count == 1)
  }

  @Test func unavailableRememberedFolderDoesNotHideRetainedRecoveryHistory() async throws {
    let fixture = try WorkspaceFixture(count: 1)
    defer { fixture.remove() }
    let original = TaskCoordinator(bookmarkFile: fixture.bookmark)
    _ = try await original.selectFolderForWriting(fixture.folder)
    let plan = try await original.planSortByType(request: "Sort by type")
    _ = try await original.execute(plan)
    try Data("unavailable remembered grant".utf8).write(to: fixture.bookmark)
    let model = WorkspaceModel(
      coordinator: TaskCoordinator(bookmarkFile: fixture.bookmark), modelIsReady: { true },
      completion: { _, _, _ in sortResponse })
    model.windowDidOpen()
    model.restoreIfNeeded()
    await model.waitUntilFinished()
    #expect(model.inventory == nil)
    #expect(model.feedback?.kind == .failure)
    #expect(model.history?.operations.count == 1)
    #expect(model.recovery.count == 1)
  }

  @Test func closedWorkspaceCannotStartTaskUntilReopened() async throws {
    let fixture = try WorkspaceFixture(count: 1)
    defer { fixture.remove() }
    let coordinator = TaskCoordinator(bookmarkFile: fixture.bookmark)
    let model = WorkspaceModel(
      coordinator: coordinator, modelIsReady: { true },
      completion: { _, _, _ in sortResponse })
    model.windowDidOpen()
    model.inspect(fixture.folder, forWriting: true)
    await model.waitUntilFinished()
    #expect(model.canSubmit)
    model.closeWindow()
    #expect(!model.canSubmit)
    model.submit()
    #expect(model.phase == .idle)
    #expect(try await coordinator.historySnapshot().operations.isEmpty)
    model.windowDidOpen()
    model.submit()
    await model.waitUntilFinished()
    #expect(model.result?.changed.count == 1)
  }

  @Test func refreshingSameFolderRetainsInventoryAndComposerContext() async throws {
    let fixture = try WorkspaceFixture(count: 2)
    defer { fixture.remove() }
    let model = WorkspaceModel(
      coordinator: TaskCoordinator(bookmarkFile: fixture.bookmark),
      modelIsReady: { true }, completion: { _, _, _ in sortResponse })
    model.windowDidOpen()
    model.inspect(fixture.folder, forWriting: true)
    await model.waitUntilFinished()
    let names = model.inventory?.items.map(\.name)
    let selectedFolder = try #require(model.inventory?.folder)
    model.request = "Group by modification month"
    model.inspect()
    #expect(model.phase == .inspecting)
    #expect(model.inventory?.folder == selectedFolder)
    #expect(model.inventory?.items.map(\.name) == names)
    #expect(model.request == "Group by modification month")
    await model.waitUntilFinished()
    #expect(model.inventory?.items.map(\.name) == names)
    #expect(!model.isBusy)
  }
}

private let sortResponse =
  #"{"status":"plan","message":"","clauses":[{"text":"Sort by type","effect":"sort"}],"sort":{"kind":"type","evidence":"Sort by type","value":""},"rename":[],"selection":{"extensions":[],"nameContains":"","evidence":""},"files":"all"}"#

actor PlanningGate {
  private var continuation: CheckedContinuation<Void, Never>?
  private var started: CheckedContinuation<Void, Never>?
  private(set) var calls = 0

  func complete() async -> String {
    calls += 1
    started?.resume()
    started = nil
    await withCheckedContinuation { continuation = $0 }
    return sortResponse
  }

  func waitUntilStarted() async {
    if calls > 0 { return }
    await withCheckedContinuation { started = $0 }
  }

  func release() {
    continuation?.resume()
    continuation = nil
  }
}

private final class WorkspaceCheckpointGate: Sendable {
  private struct State: Sendable {
    var paused = false
    var waiter: CheckedContinuation<Void, Never>?
  }
  private let state = OSAllocatedUnfairLock(initialState: State())
  private let release = DispatchSemaphore(value: 0)

  func pauseOnce() {
    let pause = state.withLock { state in
      guard !state.paused else { return false }
      state.paused = true
      state.waiter?.resume()
      state.waiter = nil
      return true
    }
    if pause { release.wait() }
  }

  func waitUntilPaused() async {
    await withCheckedContinuation { continuation in
      state.withLock { state in
        if state.paused { continuation.resume() } else { state.waiter = continuation }
      }
    }
  }

  func resume() { release.signal() }
}

private enum WorkspaceFixtureError: Error { case interrupted }

@MainActor private final class ReadinessFixture {
  var ready = false
}

private struct WorkspaceFixture: Sendable {
  let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
    .appendingPathComponent("tidy-workspace-tests-\(UUID())")
  var folder: URL { root.appendingPathComponent("Selected") }
  var bookmark: URL { root.appendingPathComponent("settings/folder.bookmark") }

  init(count: Int) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for index in 0..<count {
      try Data("PRIVATE FIXTURE CONTENT".utf8).write(
        to: folder.appendingPathComponent("file-\(index).txt"))
    }
  }

  func remove() { try? FileManager.default.removeItem(at: root) }
}
