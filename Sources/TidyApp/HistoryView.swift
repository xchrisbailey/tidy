import AppKit
import SwiftUI
import TidyCore

struct HistoryView: View {
  let coordinator: TaskCoordinator
  @Environment(\.scenePhase) private var scenePhase
  @State private var snapshot: HistorySnapshot?
  @State private var errorMessage: String?
  @State private var isWorking = false
  @State private var confirmsClear = false

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("Undo history").font(.title)
        Spacer()
        Button("Refresh") { refresh() }
        Button("Clear History…", role: .destructive) { confirmsClear = true }
          .disabled(snapshot?.operations.isEmpty != false)
      }
      Text(
        "Recovery records are kept on this Mac until you explicitly clear them. They contain paths and recovery information, not document excerpts. History is not a backup."
      )
      if let snapshot {
        Text(
          "Recovery records: \(ByteCountFormatter.string(fromByteCount: snapshot.recordBytes, countStyle: .file)) (\(snapshot.recordBytes) bytes)"
        )
        .accessibilityIdentifier("history-storage")
        Text("Excludes folder grants, model storage and lock bookkeeping.")
          .font(.caption).foregroundStyle(.secondary)
        if snapshot.operations.isEmpty {
          ContentUnavailableView("No retained history", systemImage: "clock.arrow.circlepath")
        } else {
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
              ForEach(snapshot.operations.reversed()) { entry in
                VStack(alignment: .leading, spacing: 8) {
                  HStack {
                    Text("Task \(entry.id.uuidString)").font(.headline)
                    Spacer()
                    Button("Undo Task") { undo(entry.id, fileOnly: false) }
                      .disabled(!entry.canAttemptUndo)
                  }
                  Text(entry.historyOutcome)
                  Text("Original: \(entry.originalPath)")
                  Text("Resulting: \(entry.resultingPath)")
                  Button("Undo File") { undo(entry.id, fileOnly: true) }
                    .disabled(!entry.canAttemptUndo)
                  Divider()
                }
                .textSelection(.enabled)
              }
            }
          }
        }
      }
      if isWorking { ProgressView().controlSize(.small) }
      if let errorMessage {
        Label(errorMessage, systemImage: "exclamationmark.triangle")
          .foregroundStyle(.orange).textSelection(.enabled)
      }
      Text(
        "Undo is best-effort: edits are preserved only when the same file can be identified. Occupied original locations are never overwritten. Grant write access to the recorded original folder before undoing if needed."
      )
      .font(.caption).foregroundStyle(.secondary)
      Button("Grant Original Folder Access…") { grantFolder() }
    }
    .padding(24)
    .frame(minWidth: 720, minHeight: 480)
    .disabled(isWorking)
    .task { refresh() }
    .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
    .alert("Permanently clear undo history?", isPresented: $confirmsClear) {
      Button("Cancel", role: .cancel) {}
      Button("Clear History and Lose Undo", role: .destructive) {
        perform { try await coordinator.clearHistory(confirmingUndoLoss: true) }
      }
    } message: {
      Text(
        "Tidy will permanently forget all retained task and file recovery records, including interrupted changes. You will no longer be able to undo those changes with Tidy. This does not reverse changes or move, edit, or delete user files. Folder grants and downloaded models are kept."
      )
    }
  }

  private func refresh() { perform {} }

  private func undo(_ id: UUID, fileOnly: Bool) {
    perform {
      if fileOnly { try await coordinator.undoFile(id) } else { try await coordinator.undoTask(id) }
    }
  }

  private func grantFolder() {
    let panel = NSOpenPanel()
    panel.title = "Select the recorded original folder"
    panel.prompt = "Grant Write Access"
    panel.message = "Authorize undo in this folder. Granting access does not undo any changes."
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = false
    panel.resolvesAliases = false
    panel.treatsFilePackagesAsDirectories = false
    if panel.runModal() == .OK, let folder = panel.url {
      perform { _ = try await coordinator.selectFolderForWriting(folder) }
    }
  }

  private func perform(_ action: @escaping () async throws -> Void) {
    guard !isWorking else { return }
    isWorking = true
    errorMessage = nil
    Task {
      defer { isWorking = false }
      do { try await action() } catch { errorMessage = error.localizedDescription }
      do { snapshot = try await coordinator.historySnapshot() } catch {
        snapshot = nil
        errorMessage = error.localizedDescription
      }
    }
  }
}

extension FileOperation {
  fileprivate var canAttemptUndo: Bool { state != .undone && state != .notApplied }

  fileprivate var historyOutcome: String {
    switch state {
    case .intent: "Interrupted or incomplete — identity check required"
    case .completed: "Moved — available for best-effort undo"
    case .undoIntent: "Undo interrupted — identity check required"
    case .undone: "Undone"
    case .notApplied: "Not moved — interrupted before the move"
    }
  }
}
