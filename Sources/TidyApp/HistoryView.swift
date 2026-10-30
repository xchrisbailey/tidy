import AppKit
import SwiftUI
import TidyCore

struct HistoryView: View {
  let coordinator: TaskCoordinator
  @Environment(\.scenePhase) private var scenePhase
  @State private var snapshot: HistorySnapshot?
  @State private var recovery: [RecoveryOperation] = []
  @State private var errorMessage: String?
  @State private var isWorking = false
  @State private var confirmsClear = false
  @State private var undoActivity = HistoryUndo()

  private var isBusy: Bool { isWorking || undoActivity.isWorking }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("Undo history").font(.title)
        Spacer()
        Button("Refresh") { refresh() }
        Button("Clear History…", role: .destructive) { confirmsClear = true }
          .disabled(snapshot?.operations.isEmpty != false)
      }
      .disabled(isBusy)
      Text(
        "Recovery records are kept on this Mac until you explicitly clear them. They contain paths and recovery information, not document excerpts. History is not a backup."
      )
      Text(
        "Reopening checks actual file identities. Interrupted changes never resume automatically.")
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
              ForEach(snapshot.tasks.reversed()) { task in
                VStack(alignment: .leading, spacing: 8) {
                  HStack {
                    Text("Task \(task.id.uuidString)").font(.headline)
                    Spacer()
                    Button("Undo Task") { undo(task.id, fileOnly: false) }
                      .disabled(!task.operations.contains { canUndo($0.id) })
                  }
                  Text("\(task.operations.count) recorded files")
                  ForEach(task.operations) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                      if let report = recovery.first(where: { $0.id == entry.id }) {
                        Text(report.status.rawValue.capitalized)
                        Text(report.explanation)
                      } else {
                        Text(entry.state.explanation)
                      }
                      Text("Original: \(entry.originalPath)")
                      Text("Resulting: \(entry.resultingPath)")
                      Button("Undo File") { undo(entry.id, fileOnly: true) }
                        .disabled(!canUndo(entry.id))
                      if recovery.first(where: { $0.id == entry.id })?.options.contains(
                        .cleanupFolders) == true
                      {
                        Button("Clean Up Empty Task Folders") { undo(entry.id, fileOnly: true) }
                      }
                    }
                  }
                  Divider()
                }
                .textSelection(.enabled)
              }
            }
          }
          .disabled(isBusy)
        }
      }
      if isWorking { ProgressView().controlSize(.small) }
      if undoActivity.isWorking {
        HStack {
          if let progress = undoActivity.progress {
            ProgressView(value: Double(progress.processed), total: Double(max(progress.total, 1)))
              .accessibilityLabel("Undo progress")
              .accessibilityValue(
                "\(progress.processed) of \(progress.total) checked; \(progress.undone) undone")
          } else {
            ProgressView().controlSize(.small)
          }
          Button(undoActivity.isCancelling ? "Cancelling…" : "Cancel Undo") {
            undoActivity.cancel()
          }
          .disabled(undoActivity.isCancelling)
          .accessibilityIdentifier("history-cancel-undo")
        }
      }
      if let message = undoActivity.message {
        Text(message).accessibilityIdentifier("history-undo-progress")
      }
      if let errorMessage {
        Label(errorMessage, systemImage: "exclamationmark.triangle")
          .foregroundStyle(.orange).textSelection(.enabled)
      }
      Text(
        "Undo is best-effort: edits are preserved only when the same file can be identified. Occupied original locations are never overwritten. Grant write access to the recorded original folder before undoing if needed."
      )
      .font(.caption).foregroundStyle(.secondary)
      Button("Grant Original Folder Access…") { grantFolder() }
        .disabled(isBusy)
    }
    .padding(24)
    .frame(minWidth: 720, minHeight: 480)
    .task { refresh() }
    .onDisappear { undoActivity.cancel() }
    .onChange(of: undoActivity.isWorking) { _, working in if !working { refresh() } }
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

  private func canUndo(_ id: UUID) -> Bool {
    recovery.first(where: { $0.id == id })?.options.contains(.undoFile) == true
  }

  private func undo(_ id: UUID, fileOnly: Bool) {
    guard !isBusy else { return }
    undoActivity.start(id, fileOnly: fileOnly, coordinator: coordinator)
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
    guard !isBusy else { return }
    isWorking = true
    errorMessage = nil
    Task {
      defer { isWorking = false }
      do { try await action() } catch { errorMessage = error.localizedDescription }
      do {
        recovery = try await coordinator.recoveryReport()
        snapshot = try await coordinator.historySnapshot()
      } catch {
        snapshot = nil
        recovery = []
        errorMessage = error.localizedDescription
      }
    }
  }
}
