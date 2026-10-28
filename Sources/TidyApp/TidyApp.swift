import AppKit
import SwiftUI
import TidyCore

@main
struct TidyApp: App {
  private let coordinator = TaskCoordinator(
    bookmarkFile: URL.applicationSupportDirectory
      .appendingPathComponent("Tidy", isDirectory: true)
      .appendingPathComponent("selected-folder.bookmark")
  )

  var body: some Scene {
    Window("Tidy", id: "inventory") {
      InventoryView(coordinator: coordinator)
    }
    .defaultSize(width: 820, height: 600)
  }
}

private struct InventoryView: View {
  let coordinator: TaskCoordinator
  @State private var inventory: FolderInventory?
  @State private var errorMessage: String?
  @State private var isInspecting = false
  @State private var isMutating = false
  @State private var operation: Task<Void, Never>?
  @State private var request = "Sort by type"
  @State private var resultMessage: String?
  @State private var history: [FileOperation] = []
  @State private var pendingPlan: SortPlan?
  @State private var showConfirmation = false
  @State private var batchProgress: BatchProgress?
  @State private var batchResult: BatchResult?

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        VStack(alignment: .leading) {
          Text("Folder inventory").font(.title)
          Text("Local • Direct children only").foregroundStyle(.secondary)
        }
        Spacer()
        Button("Inspect Folder…") { selectFolder() }
          .disabled(isInspecting)
        Button("Grant Write Access…") { selectFolder(forWriting: true) }
          .disabled(isInspecting)
        Button("Refresh") { inspect() }
          .disabled(isInspecting)
      }

      Text(
        "Inventory reads names and metadata, not file contents. Sorting requires a separate write grant and runs immediately, without a plan preview."
      )
      .font(.callout)
      Text(
        "Already-downloaded files in synced folders can be eligible. Your existing sync service may transmit file moves."
      )
      .font(.callout).foregroundStyle(.secondary)

      if isInspecting {
        HStack {
          ProgressView().controlSize(.small)
          if let batchProgress {
            ProgressView(value: Double(batchProgress.processed), total: Double(max(1, batchProgress.total)))
              .frame(width: 140)
            Text("\(batchProgress.processed)/\(batchProgress.total) processed · \(batchProgress.changed) changed")
          } else {
            Text("Working locally…")
          }
          Button("Cancel") { operation?.cancel() }
        }
      }
      if let errorMessage {
        Label(errorMessage, systemImage: "exclamationmark.triangle")
          .foregroundStyle(.orange)
          .textSelection(.enabled)
      }
      if let resultMessage {
        Text(resultMessage).textSelection(.enabled).accessibilityIdentifier("task-result")
      }
      if let batchResult {
        DisclosureGroup("Per-file results") {
          ScrollView {
            VStack(alignment: .leading) {
              ForEach(batchResult.changed) { entry in
                Text("Changed: \(entry.originalName) → \(entry.destinationFolder)/\(entry.destinationName)")
              }
              ForEach(Array((batchResult.unchanged + batchResult.skipped + batchResult.failed).enumerated()), id: \.offset) { _, outcome in
                Text("\(outcome.name): \(outcome.explanation)")
              }
              ForEach(batchResult.unprocessed, id: \.self) { name in
                Text("\(name): Not processed after cancellation or failure.")
              }
            }.frame(maxWidth: .infinity, alignment: .leading)
          }.frame(maxHeight: 140)
        }
      }
      HStack {
        TextField("Request", text: $request)
          .accessibilityIdentifier("sort-request")
        Button("Run") { submit() }
          .disabled(isInspecting || inventory == nil)
      }
      Text(
        "‘Sort by type’ organizes up to 1,000 eligible direct child files. More than 100 changed files requires confirmation. Unknown extensions are skipped; existing folders are not traversed."
      )
      .font(.caption).foregroundStyle(.secondary)
      if let inventory {
        Text(inventory.folder.path).font(.headline).textSelection(.enabled)
        Text(
          "\(inventory.candidateFiles.count) eligible files · \(inventory.skippedItems.count) skipped items"
        )
        .accessibilityIdentifier("inventory-counts")
        Table(inventory.items) {
          TableColumn("Name", value: \.name)
          TableColumn("Eligibility") { item in
            Text(item.skipReason?.explanation ?? "Eligible — metadata only")
          }
          TableColumn("Size") { item in
            if let size = item.byteCount {
              Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
            } else {
              Text("—")
            }
          }.width(90)
        }
        if inventory.items.isEmpty {
          Text("This folder is empty. No files were changed.").foregroundStyle(.secondary)
        }
      } else if !isInspecting {
        ContentUnavailableView(
          "Select a folder", systemImage: "folder",
          description: Text(
            "Grant access to just the folder you want to inspect. Tidy remembers that grant on this Mac."
          )
        )
      }
      Spacer(minLength: 0)
      if !history.isEmpty {
        Text("Undo history").font(.headline)
        ScrollView {
          VStack(alignment: .leading, spacing: 8) {
            ForEach(history.reversed()) { entry in
              VStack(alignment: .leading) {
                Text("\(entry.originalName) → \(entry.destinationFolder)/\(entry.destinationName)")
                Text(entry.selectedFolderPath).font(.caption).textSelection(.enabled)
                HStack {
                  Text(entry.state.explanation).font(.caption)
                  if entry.state != .undone && entry.state != .notApplied {
                    Button("Undo Task") { undo(entry.taskID, fileOnly: false) }
                    Button("Undo File") { undo(entry.id, fileOnly: true) }
                  }
                }
              }
            }
          }
        }.frame(maxHeight: 150).disabled(isInspecting)
        Text(
          "Undo preserves edits only when the same file can be identified. Occupied locations and uncertain identities are never overwritten. Re-grant the original folder if you have selected another one."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
    }
    .padding(24)
    .frame(minWidth: 720, minHeight: 480)
    .task { inspect() }
    .onDisappear { operation?.cancel() }
    .alert("Confirm large task", isPresented: $showConfirmation) {
      Button("Cancel", role: .cancel) { pendingPlan = nil }
      Button("Continue") {
        if let plan = pendingPlan { runBatch(plan, confirmed: true) }
        pendingPlan = nil
      }
    } message: {
      if let plan = pendingPlan {
        Text("Change \(plan.changedCount) distinct files: \(plan.renameCount) renames and \(plan.moveCount) moves. A file renamed and moved counts once. Completed changes can be undone; nothing will be overwritten.")
      }
    }
  }

  private func selectFolder(forWriting: Bool = false) {
    let panel = NSOpenPanel()
    panel.title = forWriting ? "Select a folder to organize" : "Select a folder to inspect"
    panel.prompt = forWriting ? "Grant Write Access" : "Grant Read Access"
    panel.message =
      forWriting
      ? "Allow Tidy to move files and create sorting folders here, and undo its changes. Only this folder is authorized."
      : "Tidy only inventories direct children. This does not authorize sorting or undo."
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = false
    panel.resolvesAliases = false
    panel.treatsFilePackagesAsDirectories = false
    if panel.runModal() == .OK, let folder = panel.url {
      inspect(folder, forWriting: forWriting)
    }
  }

  private func inspect(_ folder: URL? = nil, forWriting: Bool = false) {
    guard !isInspecting else { return }
    isInspecting = true
    errorMessage = nil
    inventory = nil
    operation = Task {
      defer { isInspecting = false }
      do {
        if let folder {
          inventory =
            try await
            (forWriting
            ? coordinator.selectFolderForWriting(folder) : coordinator.selectFolder(folder))
        } else {
          inventory = try await coordinator.restoreFolder()
        }
      } catch is CancellationError {
        errorMessage = "Inventory cancelled. No files were changed."
      } catch {
        errorMessage = error.localizedDescription
      }
      do { history = try await coordinator.undoHistory() } catch {
        errorMessage = error.localizedDescription
      }
    }
  }

  private func submit() {
    let submitted = request
    mutate {
      let plan = try await coordinator.planSortByType(request: submitted)
      if plan.requiresConfirmation {
        pendingPlan = plan
        showConfirmation = true
        return "Awaiting confirmation: \(plan.changedCount) files, \(plan.renameCount) renames, \(plan.moveCount) moves. No files changed."
      }
      return try await executeBatch(plan)
    }
  }

  private func runBatch(_ plan: SortPlan, confirmed: Bool) {
    mutate { try await executeBatch(plan, confirmed: confirmed) }
  }

  private func executeBatch(_ plan: SortPlan, confirmed: Bool = false) async throws -> String {
    let result = try await coordinator.execute(plan, confirmed: confirmed) { progress in
      await MainActor.run { batchProgress = progress }
    }
    batchResult = result
    return result.explanation
  }

  private func undo(_ id: UUID, fileOnly: Bool) {
    mutate {
      if fileOnly { try await coordinator.undoFile(id) } else { try await coordinator.undoTask(id) }
      return
        "Undo request finished. See the recorded status below; no existing files were overwritten."
    }
  }

  private func mutate(_ action: @escaping () async throws -> String) {
    guard !isInspecting else { return }
    isInspecting = true
    isMutating = true
    errorMessage = nil
    resultMessage = nil
    batchResult = nil
    batchProgress = nil
    operation = Task {
      defer {
        isInspecting = false
        isMutating = false
        batchProgress = nil
      }
      do { resultMessage = try await action() } catch { errorMessage = error.localizedDescription }
      do {
        history = try await coordinator.undoHistory()
        if Task.isCancelled { inventory = nil } else {
          inventory = try await coordinator.restoreFolder()
        }
      } catch { errorMessage = error.localizedDescription }
    }
  }
}

extension OperationState {
  fileprivate var explanation: String {
    switch self {
    case .intent: "Interrupted or incomplete — identity check required"
    case .completed: "Moved — available for undo"
    case .undoIntent: "Undo interrupted — identity check required"
    case .undone: "Undone"
    case .notApplied: "Not moved — interrupted before the move"
    }
  }
}

extension SkipReason {
  fileprivate var explanation: String {
    switch self {
    case .hidden: "Skipped — hidden item"
    case .package: "Skipped — app bundle or package"
    case .link: "Skipped — link or alias"
    case .incompleteDownload: "Skipped — incomplete download"
    case .cloudOnly: "Skipped — cloud-only; not downloaded"
    case .folder: "Skipped — existing folder; not traversed"
    case .unsupportedFile: "Skipped — not an ordinary file"
    case .unavailable: "Skipped — metadata unavailable or access denied"
    }
  }
}
