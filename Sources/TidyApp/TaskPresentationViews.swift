import SwiftUI
import TidyCore

struct TaskComposerView: View {
  @Bindable var model: WorkspaceModel
  let modelReady: Bool
  var geometry: WorkspaceGeometry? = nil
  @Environment(\.openSettings) private var openSettings
  @State private var showsHelp = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("What would you like to organize?").font(.headline)
      HStack(alignment: .top, spacing: 12) {
        TextField("For example, sort by type", text: $model.request, axis: .vertical)
          .lineLimit(1...3).textFieldStyle(.roundedBorder)
          .accessibilityLabel("Organizing request").accessibilityIdentifier("sort-request")
          .disabled(model.isBusy)
        if modelReady {
          Button("Organize Files") { model.submit() }
            .buttonStyle(.borderedProminent).disabled(!model.canSubmit)
            .help("Changes files immediately · ⌘Return")
        } else {
          Button("Set Up Model…") { openSettings() }.buttonStyle(.borderedProminent)
        }
      }
      HStack {
        Menu("Try an example") {
          Button("Sort by type") { model.request = "Sort by type" }
          Button("Group by modification month") { model.request = "Group by modification month" }
          Button("Lowercase filenames") { model.request = "Lowercase filenames" }
        }.menuStyle(.borderlessButton).fixedSize().disabled(model.isBusy)
        Spacer()
        Button {
          showsHelp.toggle()
        } label: {
          Label("How Tidy Works", systemImage: "questionmark.circle")
        }
        .buttonStyle(.borderless)
        .popover(isPresented: $showsHelp) { TaskHelpView() }
      }
      Text("Direct-child files only, unless your request explicitly includes subfolders.")
        .font(.caption).foregroundStyle(.secondary)
      Text("Table filters and selections don’t change the task’s scope.")
        .font(.caption).foregroundStyle(.secondary)
      Text("Changes files immediately. Undo is best-effort, not a backup.")
        .font(.caption).foregroundStyle(.secondary)
      Text("In a synced folder, your sync service may transmit changes.")
        .font(.caption).foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("workspace-task-composer")
    .background(WorkspaceRegion(name: "workspace-task-composer", geometry: geometry))
  }
}

struct WorkspaceActivity: View {
  let model: WorkspaceModel
  @Binding var showsResults: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if model.isBusy && model.phase != .confirming {
        HStack(spacing: 12) {
          if model.undoActivity.isWorking, let progress = model.undoActivity.progress {
            ProgressView(value: Double(progress.processed), total: Double(max(1, progress.total)))
              .frame(width: 100).accessibilityLabel("Undo progress")
            Text("\(progress.processed) of \(progress.total) checked · \(progress.undone) undone")
          } else if let progress = model.progress {
            ProgressView(value: Double(progress.processed), total: Double(max(1, progress.total)))
              .frame(width: 100).accessibilityLabel("Task progress")
            Text(
              "\(progress.processed) of \(progress.total) planned changes processed · \(progress.changed) changed"
            )
          } else {
            ProgressView().controlSize(.small)
            Text(model.phase.label)
          }
          Spacer(minLength: 8)
          Button(model.phase == .cancelling ? "Stopping…" : "Cancel") { model.cancel() }
            .disabled(!model.canCancel)
            .accessibilityIdentifier("cancel-workspace-task")
        }
      } else if let feedback = model.feedback {
        HStack(alignment: .top) {
          Label(feedback.title, systemImage: feedback.symbol).fontWeight(.medium)
          Spacer()
          Button("Details") { showsResults = true }
          if model.result != nil {
            Button("View History") { model.destination = .history }
          }
        }
        Text(feedback.detail).foregroundStyle(.secondary).lineLimit(2)
          .help(feedback.detail).accessibilityIdentifier("task-result")
      }
      if let error = model.refreshError {
        Label(error, systemImage: "exclamationmark.triangle").lineLimit(2).help(error)
      }
    }
    .font(.callout)
    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    .padding(.horizontal, 20).padding(.vertical, 8)
    .accessibilityElement(children: .contain)
  }
}

struct TaskResultsView: View {
  let result: BatchResult?
  let feedback: WorkspaceFeedback?
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(feedback?.title ?? "Task Details").font(.title2.weight(.semibold))
      if let feedback { Text(feedback.detail).textSelection(.enabled) }
      if let result {
        List {
          if !result.changed.isEmpty {
            Section("Changed · \(result.changed.count)") {
              ForEach(result.changed) { entry in
                VStack(alignment: .leading, spacing: 4) {
                  Text(entry.originalName).fontWeight(.medium)
                  Text("→ \(entry.destinationFolder)/\(entry.destinationName)").foregroundStyle(
                    .secondary)
                }.textSelection(.enabled)
              }
            }
          }
          outcomes("Unchanged", result.unchanged)
          outcomes("Not enough evidence", result.abstained)
          outcomes("Skipped", result.skipped)
          outcomes("Failed", result.failed)
          if !result.unprocessed.isEmpty {
            Section("Not processed · \(result.unprocessed.count)") {
              ForEach(result.unprocessed, id: \.self) { name in
                VStack(alignment: .leading, spacing: 4) {
                  Text(name)
                  Text("Not processed after cancellation or failure.").foregroundStyle(.secondary)
                }.textSelection(.enabled)
              }
            }
          }
        }
      } else {
        Spacer(minLength: 0)
      }
      HStack {
        Spacer()
        Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
      }
    }
    .padding(24).frame(width: 640, height: 510)
  }

  @ViewBuilder private func outcomes(_ title: String, _ entries: [FileOutcome]) -> some View {
    if !entries.isEmpty {
      Section("\(title) · \(entries.count)") {
        ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
          VStack(alignment: .leading, spacing: 4) {
            Text(entry.name).fontWeight(.medium)
            Text(entry.explanation).foregroundStyle(.secondary)
          }.textSelection(.enabled)
        }
      }
    }
  }
}

private struct TaskHelpView: View {
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Text("How Tidy Works").font(.title2.weight(.semibold))
        Text(
          "Describe how to group or rename files. Try file type, filename or modification dates, letter case, separators, or a quoted prefix or suffix."
        )
        Text("Folder access").font(.headline)
        Text(
          "Inspection reads names and metadata. Changing files requires a separate write grant for the folder. No plan preview is shown; more than 100 distinct changes needs confirmation. A task is limited to 1,000 candidate files."
        )
        Text("Content-based names").font(.headline)
        Text(
          "When requested, Tidy reads supported UTF-8 text and Markdown, PDFs, and PNG, JPEG, HEIC/HEIF and single-image TIFF images locally within inspection limits. PDF naming uses at most the first three pages, including text recognition. Protected PDFs are not used. Unsupported or insufficient evidence leaves files unchanged."
        )
        Text("Scope and privacy").font(.headline)
        Text(
          "Only direct-child files are included unless you explicitly request subfolders. Existing folders are never renamed or moved. Cloud-only files are skipped, not downloaded. Tasks run locally; model setup is the only network download. Your existing sync service may transmit changes in synced folders."
        )
        Text("Recovery").font(.headline)
        Text(
          "Cancellation keeps completed changes. History records paths and recovery information on this Mac until you clear it. Undo is best-effort: occupied locations and uncertain file identities are never overwritten. History is not a backup."
        )
      }.padding(20)
    }.frame(width: 390, height: 440)
  }
}
