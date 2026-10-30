import Foundation
import Observation
import TidyCore

enum WorkspaceDestination: String, CaseIterable, Identifiable {
  case organize = "Organize"
  case history = "History"
  var id: Self { self }
  var symbol: String { self == .organize ? "folder" : "clock.arrow.circlepath" }
}

enum WorkspacePhase: Equatable {
  case idle, inspecting, planning, confirming, executing, undoing, cancelling, refreshing

  var label: String {
    switch self {
    case .idle: "Ready"
    case .inspecting: "Inspecting folder…"
    case .planning: "Understanding your request locally…"
    case .confirming: "Waiting for confirmation"
    case .executing: "Organizing files…"
    case .undoing: "Checking and undoing recorded changes…"
    case .cancelling: "Stopping safely…"
    case .refreshing: "Refreshing files and history…"
    }
  }
}

struct WorkspaceFeedback {
  enum Kind: Equatable { case information, success, cancelled, failure }
  let kind: Kind
  let title: String
  let detail: String

  var symbol: String {
    switch kind {
    case .information: "info.circle"
    case .success: "checkmark.circle"
    case .cancelled: "stop.circle"
    case .failure: "exclamationmark.triangle"
    }
  }
}

/// Owns task lifetime independently of which sidebar destination is being shown.
/// All file authority and durable recovery remain with the existing coordinator.
@Observable @MainActor
final class WorkspaceModel {
  let coordinator: TaskCoordinator
  let undoActivity = HistoryUndo()
  var destination: WorkspaceDestination? = .organize
  var request = "Sort by type"
  private(set) var inventory: FolderInventory?
  private(set) var phase: WorkspacePhase = .idle
  private(set) var progress: BatchProgress?
  private(set) var result: BatchResult?
  private(set) var feedback: WorkspaceFeedback?
  private(set) var inventoryRefreshError: String?
  private(set) var historyRefreshError: String?
  private(set) var pendingPlan: SortPlan?
  private(set) var history: HistorySnapshot?
  private(set) var recovery: [RecoveryOperation] = []
  private(set) var accessDescription = "Folder access is checked before changes"
  @ObservationIgnored private let modelIsReady: @MainActor () -> Bool
  @ObservationIgnored private let completion: PlanCompletion
  @ObservationIgnored private var operation: Task<Void, Never>?
  @ObservationIgnored private var restored = false

  init(
    coordinator: TaskCoordinator,
    modelIsReady: @escaping @MainActor () -> Bool,
    completion: @escaping PlanCompletion
  ) {
    self.coordinator = coordinator
    self.modelIsReady = modelIsReady
    self.completion = completion
  }

  var isBusy: Bool { phase != .idle || undoActivity.isWorking }
  var refreshError: String? {
    let messages = [inventoryRefreshError, historyRefreshError].compactMap { $0 }
    return messages.isEmpty ? nil : messages.joined(separator: "\n")
  }
  var canSubmit: Bool {
    !isBusy && inventory != nil && modelIsReady()
      && !request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
  var canCancel: Bool {
    isBusy && phase != .cancelling && phase != .confirming
  }

  func restoreIfNeeded() {
    guard !restored, !isBusy else { return }
    restored = true
    inspect()
  }

  func inspect(_ folder: URL? = nil, forWriting: Bool = false) {
    guard !isBusy else { return }
    restored = true
    clearOutcome()
    start(.inspecting) {
      self.inventory = nil
      if let folder {
        self.inventory =
          try await
          (forWriting
          ? self.coordinator.selectFolderForWriting(folder)
          : self.coordinator.selectFolder(folder))
        self.accessDescription =
          forWriting
          ? "Write access granted for this folder"
          : "Read access · changes require a separate write grant"
      } else {
        self.inventory = try await self.coordinator.restoreFolder()
      }
    }
  }

  func submit() {
    guard !isBusy, inventory != nil,
      !request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return }
    let submitted = request
    clearOutcome()
    start(.planning) {
      guard self.modelIsReady() else {
        await self.coordinator.recordDiagnostic(.modelUnavailable)
        self.feedback = WorkspaceFeedback(
          kind: .information, title: "Set up the local model",
          detail:
            "Open Settings to finish setup or check the installed model offline. No files changed.")
        return
      }
      switch try await self.coordinator.planTask(request: submitted, model: self.completion) {
      case .clarification(let question):
        self.feedback = WorkspaceFeedback(
          kind: .information, title: "A little more detail is needed",
          detail: "\(question) Edit your request and choose Organize Files again. No files changed."
        )
      case .unsupported(let reason):
        self.feedback = WorkspaceFeedback(
          kind: .information, title: "That request isn’t supported",
          detail: "\(reason) No files changed.")
      case .plan(let plan):
        try Task.checkCancellation()
        if plan.requiresConfirmation {
          self.pendingPlan = plan
        } else {
          try await self.execute(plan, confirmed: false)
        }
      }
    }
  }

  func confirmPlan() {
    guard phase == .confirming, let plan = pendingPlan, operation == nil else { return }
    pendingPlan = nil
    phase = .idle
    start(.executing) { try await self.execute(plan, confirmed: true) }
  }

  func dismissPlan() {
    guard phase == .confirming else { return }
    pendingPlan = nil
    phase = .idle
    feedback = WorkspaceFeedback(
      kind: .cancelled, title: "Task not started",
      detail: "Confirmation was cancelled. No files changed.")
  }

  func cancel() {
    guard canCancel else { return }
    phase = .cancelling
    if undoActivity.isWorking { undoActivity.cancel() } else { operation?.cancel() }
  }

  func closeWindow() {
    if phase == .confirming { dismissPlan() } else { cancel() }
  }

  func refreshHistory() {
    guard !isBusy else { return }
    start(.refreshing) { await self.reloadHistory() }
  }

  func canUndo(_ id: UUID) -> Bool {
    !isBusy && recovery.contains { $0.id == id && $0.options.contains(.undoFile) }
  }

  func canUndoTask(_ id: UUID) -> Bool {
    !isBusy && recovery.contains { $0.operation.taskID == id && $0.options.contains(.undoTask) }
  }

  func canCleanUp(_ id: UUID) -> Bool {
    !isBusy && recovery.contains { $0.id == id && $0.options.contains(.cleanupFolders) }
  }

  func undo(_ id: UUID, fileOnly: Bool) {
    guard !isBusy else { return }
    guard fileOnly ? (canUndo(id) || canCleanUp(id)) : canUndoTask(id) else { return }
    clearOutcome()
    phase = .undoing
    undoActivity.start(id, fileOnly: fileOnly, coordinator: coordinator)
    operation = Task {
      await undoActivity.waitUntilFinished()
      feedback = WorkspaceFeedback(
        kind: phase == .cancelling ? .cancelled : .information,
        title: "Undo status", detail: undoActivity.message ?? "Check each recorded file’s status.")
      await reloadAfterChanges()
      phase = .idle
      operation = nil
    }
  }

  func clearHistory() {
    guard !isBusy else { return }
    clearOutcome()
    start(.refreshing) {
      try await self.coordinator.clearHistory(confirmingUndoLoss: true)
      await self.reloadHistory()
      self.feedback = WorkspaceFeedback(
        kind: .information, title: "History cleared",
        detail:
          "Recovery records were removed. User files, models, and folder grants were not changed.")
    }
  }

  func waitUntilFinished() async { await operation?.value }

  private func execute(_ plan: SortPlan, confirmed: Bool) async throws {
    phase = .executing
    let result = try await coordinator.execute(plan, confirmed: confirmed) { progress in
      await self.updateProgress(progress)
    }
    self.result = result
    feedback = WorkspaceFeedback(
      kind: result.cancelled ? .cancelled : result.isPartial ? .failure : .success,
      title: result.cancelled ? "Task cancelled" : result.isPartial ? "Task stopped" : "Finished",
      detail: result.explanation)
    await reloadAfterChanges()
  }

  private func updateProgress(_ progress: BatchProgress) { self.progress = progress }

  private func start(_ phase: WorkspacePhase, action: @escaping @MainActor () async throws -> Void)
  {
    guard operation == nil else { return }
    self.phase = phase
    operation = Task {
      do {
        try await action()
      } catch is CancellationError {
        feedback = WorkspaceFeedback(
          kind: .cancelled, title: "Stopped",
          detail:
            "The request was cancelled. Check History for any completed changes; nothing was rolled back automatically."
        )
        if phase == .planning || phase == .executing { await reloadAfterChanges() }
      } catch {
        feedback = WorkspaceFeedback(
          kind: .failure, title: "Couldn’t finish", detail: error.localizedDescription)
        if phase == .planning || phase == .executing { await reloadAfterChanges() }
      }
      if phase == .inspecting { await reloadHistory() }
      self.phase = pendingPlan == nil ? .idle : .confirming
      operation = nil
    }
  }

  private func clearOutcome() {
    feedback = nil
    inventoryRefreshError = nil
    historyRefreshError = nil
    result = nil
    progress = nil
  }

  private func reloadAfterChanges() async {
    // Refresh is deliberately outside the cancelled task: completed operations stay
    // visible, and an inventory refresh failure must not erase the durable result.
    let coordinator = coordinator
    inventoryRefreshError = nil
    let refreshed = await Task.detached {
      do {
        return Result<FolderInventory?, Error>.success(try await coordinator.restoreFolder())
      } catch { return Result<FolderInventory?, Error>.failure(error) }
    }.value
    switch refreshed {
    case .success(let inventory): self.inventory = inventory
    case .failure(let error):
      inventoryRefreshError = "Files could not be refreshed: \(error.localizedDescription)"
    }
    await reloadHistory()
  }

  private func reloadHistory() async {
    historyRefreshError = nil
    do {
      recovery = try await coordinator.recoveryReport()
      history = try await coordinator.historySnapshot()
    } catch {
      historyRefreshError = "History could not be refreshed: \(error.localizedDescription)"
    }
  }
}
