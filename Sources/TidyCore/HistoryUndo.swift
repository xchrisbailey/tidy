import Foundation
import Observation

/// Owns a history window's undo lifetime without changing coordinator task authority.
@Observable @MainActor
public final class HistoryUndo {
  public private(set) var isWorking = false
  public private(set) var isCancelling = false
  public private(set) var message: String?
  private var operation: Task<Void, Never>?

  public init() {}

  public func start(_ id: UUID, fileOnly: Bool, coordinator: TaskCoordinator) {
    guard !isWorking else { return }
    isWorking = true
    isCancelling = false
    message = "Checking retained undo records…"
    operation = Task {
      defer {
        isWorking = false
        isCancelling = false
        operation = nil
      }
      var selected: [FileOperation] = []
      var outcome = "Undo finished"
      do {
        selected = try await coordinator.historySnapshot().operations.filter {
          fileOnly ? $0.id == id : $0.taskID == id
        }
        message =
          "Undoing \(selected.count) recorded files. Completed reversals are kept if cancelled."
        if fileOnly {
          try await coordinator.undoFile(id)
        } else {
          try await coordinator.undoTask(id)
        }
      } catch is CancellationError {
        outcome = "Undo cancelled"
      } catch {
        outcome = "Undo stopped: \(error.localizedDescription)"
      }
      do {
        let ids = Set(selected.filter { $0.state != .undone }.map(\.id))
        let history = try await coordinator.historySnapshot()
        let undone = history.operations.filter { ids.contains($0.id) && $0.state == .undone }.count
        message =
          "\(outcome). \(undone) of \(ids.count) remaining recorded files undone. Completed reversals were not rolled back; check each file's status."
      } catch {
        message =
          "\(outcome). Status could not be refreshed; reopen history to check partial outcomes."
      }
    }
  }

  public func cancel() {
    guard isWorking else { return }
    isCancelling = true
    operation?.cancel()
  }

  public func waitUntilFinished() async {
    await operation?.value
  }
}
