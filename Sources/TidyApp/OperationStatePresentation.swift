import TidyCore

extension OperationState {
  var explanation: String {
    switch self {
    case .intent: "Interrupted or incomplete — identity check required"
    case .completed: "Changed — available for best-effort undo"
    case .undoIntent: "Undo interrupted — identity check required"
    case .undone: "Undone"
    case .notApplied: "Not changed — interrupted before the change"
    }
  }
}
