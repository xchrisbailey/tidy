import SwiftUI
import TidyCore

struct HistoryView: View {
  let model: WorkspaceModel
  @State private var selectedTask: UUID?
  @State private var selectedFile: UUID?
  @State private var showsResults = false

  private var tasks: [HistoryTask] { Array((model.history?.tasks ?? []).reversed()) }
  private var task: HistoryTask? { tasks.first { $0.id == selectedTask } }
  private var operation: FileOperation? { task?.operations.first { $0.id == selectedFile } }

  var body: some View {
    GeometryReader { viewport in
      VStack(spacing: 0) {
        if tasks.isEmpty {
          ContentUnavailableView(
            "No retained history", systemImage: "clock.arrow.circlepath",
            description: Text("Recorded changes appear here. History is not a backup.")
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          HSplitView {
            List(tasks, selection: $selectedTask) { task in
              VStack(alignment: .leading, spacing: 6) {
                Text(title(task)).font(.headline).lineLimit(1).truncationMode(.middle)
                Text("\(task.operations.count) recorded files").font(.callout)
                Text(summary(task)).font(.caption).foregroundStyle(.secondary)
              }.padding(.vertical, 6).tag(task.id)
            }.frame(minWidth: 210, idealWidth: 240, maxWidth: 310)
            taskDetail.frame(minWidth: 300)
          }.frame(minHeight: 0, maxHeight: .infinity)
        }
        WorkspaceActivity(model: model, showsResults: $showsResults)
      }
      .frame(width: viewport.size.width, height: viewport.size.height, alignment: .top)
    }
    .onChange(of: tasks.map(\.id), initial: true) { _, ids in
      if let selectedTask, ids.contains(selectedTask) { return }
      selectedTask = ids.first
    }
    .onChange(of: selectedTask) { _, _ in selectedFile = task?.operations.first?.id }
    .sheet(isPresented: $showsResults) {
      TaskResultsView(result: model.result, feedback: model.feedback)
    }
  }

  @ViewBuilder private var taskDetail: some View {
    if let task {
      VStack(alignment: .leading, spacing: 0) {
        VStack(alignment: .leading, spacing: 10) {
          HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
              Text(title(task)).font(.title2.weight(.semibold))
              Text(summary(task)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Undo Task") { model.undo(task.id, fileOnly: false) }
              .disabled(!model.canUndoTask(task.id))
          }
          if let path = task.operations.first?.selectedFolderPath {
            Text(path).font(.callout).textSelection(.enabled).lineLimit(2).truncationMode(.middle)
              .help(path)
          }
          Text("Recorded order · Date unavailable for these records")
            .font(.caption).foregroundStyle(.secondary)
        }.padding(20)
        List(task.operations, selection: $selectedFile) { entry in
          VStack(alignment: .leading, spacing: 4) {
            Text(entry.originalName).lineLimit(1).truncationMode(.middle).help(entry.originalName)
            Text(entry.state.explanation).font(.caption).foregroundStyle(.secondary)
          }.padding(.vertical, 4).tag(entry.id)
        }.frame(minHeight: 0, maxHeight: .infinity)
        if let operation {
          Divider()
          ScrollView {
            fileDetail(operation)
          }.frame(maxHeight: 230)
        }
      }
    } else {
      ContentUnavailableView("Select a task", systemImage: "clock.arrow.circlepath")
    }
  }

  private func fileDetail(_ entry: FileOperation) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      LabeledContent("Before") { Text(entry.originalPath).textSelection(.enabled) }
      LabeledContent("After") { Text(entry.resultingPath).textSelection(.enabled) }
      if let recovery = model.recovery.first(where: { $0.id == entry.id }) {
        let needsAttention =
          recovery.status == .uncertain
          || (entry.state == .completed && !recovery.options.contains(.undoFile))
        Label(
          recovery.explanation,
          systemImage: needsAttention ? "exclamationmark.triangle" : "info.circle"
        )
        .font(.callout).fixedSize(horizontal: false, vertical: true)
        HStack {
          Button("Undo File") { model.undo(entry.id, fileOnly: true) }
            .disabled(!model.canUndo(entry.id))
          if model.canCleanUp(entry.id) {
            Button("Clean Up Empty Task Folders") { model.undo(entry.id, fileOnly: true) }
          }
          if recovery.options.contains(.grantAccess) {
            Button("Grant Original Folder Access…") {
              FolderPicker.choose(
                for: model, forWriting: true,
                initialFolder: URL(fileURLWithPath: entry.selectedFolderPath))
            }.disabled(model.isBusy)
          }
        }
      }
      Text(
        "Undo preserves edits only when the same file can be identified. Occupied locations are never overwritten."
      )
      .font(.caption).foregroundStyle(.secondary)
      DisclosureGroup("Record Details") {
        Text("Task: \(entry.taskID.uuidString)").font(.caption.monospaced()).textSelection(.enabled)
        if let bytes = model.history?.recordBytes {
          Text(
            "Retained recovery records: \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) (\(bytes) bytes)"
          )
          .font(.caption).accessibilityIdentifier("history-storage")
          Text("Excludes folder grants, model storage and lock bookkeeping.").font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }.padding(20)
  }

  private func title(_ task: HistoryTask) -> String {
    guard let path = task.operations.first?.selectedFolderPath else { return "Recorded changes" }
    let name = URL(fileURLWithPath: path).lastPathComponent
    return "Changes in \(name.isEmpty ? path : name)"
  }

  private func summary(_ task: HistoryTask) -> String {
    let undone = task.operations.filter { $0.state == .undone }.count
    let changed = task.operations.filter { $0.state == .completed }.count
    let interrupted = task.operations.filter { $0.state == .intent || $0.state == .undoIntent }
      .count
    if interrupted > 0 { return "\(interrupted) interrupted · check actual state" }
    if model.recovery.contains(where: {
      $0.operation.taskID == task.id
        && ($0.status == .uncertain || $0.blockingTaskID != nil
          || ($0.operation.state == .completed && !$0.options.contains(.undoFile)))
    }) {
      return "Needs attention · \(task.operations.count) recorded files"
    }
    return "\(changed) recorded changes · \(undone) undone"
  }
}
