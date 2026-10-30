import AppKit
import SwiftUI
import TidyCore
import TidyModel

struct WorkspaceView: View {
  @Bindable var model: WorkspaceModel
  let setup: ModelSetup
  var geometry: WorkspaceGeometry? = nil
  @Environment(\.openSettings) private var openSettings
  @State private var query = ""
  @State private var selectedFiles = Set<String>()
  @State private var showsResults = false
  @State private var confirmsClear = false
  @State private var confirmsLargeTask = false

  var body: some View {
    NavigationSplitView {
      List(WorkspaceDestination.allCases, selection: $model.destination) { destination in
        Label(destination.rawValue, systemImage: destination.symbol).tag(destination)
          .accessibilityIdentifier("workspace-nav-\(destination.rawValue)")
          .background(
            WorkspaceRegion(name: "workspace-nav-\(destination.rawValue)", geometry: geometry))
      }
      .navigationSplitViewColumnWidth(min: 160, ideal: 190, max: 240)
      .safeAreaInset(edge: .bottom) {
        Button {
          openSettings()
        } label: {
          Label(
            readiness, systemImage: setup.state == .ready ? "checkmark.circle" : "arrow.down.circle"
          )
          .font(.callout)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(12)
        }
        .buttonStyle(.plain)
        .help("Open local model settings")
      }
    } detail: {
      Group {
        if model.destination == .history {
          HistoryView(model: model)
        } else {
          organize
        }
      }
      .navigationTitle(
        model.destination == .history
          ? "History" : model.inventory?.folder.lastPathComponent ?? "Organize")
    }
    .toolbar {
      if model.destination == .history {
        ToolbarItemGroup(placement: .primaryAction) {
          Button {
            model.refreshHistory()
          } label: {
            Label("Refresh History", systemImage: "arrow.clockwise")
          }
          .disabled(model.isBusy).help("Refresh history")
          Menu {
            Button("Clear History…", role: .destructive) { confirmsClear = true }
              .disabled(model.isBusy || model.history?.operations.isEmpty != false)
          } label: {
            Label("History Actions", systemImage: "ellipsis.circle")
          }
          .help("History actions")
        }
      } else {
        ToolbarItemGroup(placement: .primaryAction) {
          Button {
            FolderPicker.choose(for: model)
          } label: {
            Label("Choose Folder…", systemImage: "folder.badge.plus")
          }.disabled(model.isBusy).help("Choose a folder · ⌘O")
          Button {
            model.inspect()
          } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
          }
          .disabled(model.isBusy || model.inventory == nil).help("Refresh folder")
          Menu {
            Button("Grant Write Access…") { FolderPicker.choose(for: model, forWriting: true) }
          } label: {
            Label("Folder Access", systemImage: "lock.open")
          }
          .disabled(model.isBusy).help("Folder access")
        }
      }
    }
    .frame(minWidth: 900, minHeight: 600)
    .task {
      model.restoreIfNeeded()
      await setup.restore()
    }
    .onDisappear { model.closeWindow() }
    .onChange(of: model.inventory?.folder) { _, _ in
      query = ""
      selectedFiles = []
    }
    .onChange(of: model.inventory?.items.map(\.id)) { _, ids in
      selectedFiles.formIntersection(Set(ids ?? []))
    }
    .onChange(of: model.pendingPlan?.id) { _, id in confirmsLargeTask = id != nil }
    .alert("Confirm large task", isPresented: $confirmsLargeTask) {
      Button("Cancel", role: .cancel) { model.dismissPlan() }
      Button("Organize Files") { model.confirmPlan() }
    } message: {
      if let plan = model.pendingPlan {
        Text(
          "Change \(plan.changedCount) distinct files: \(plan.renameCount) renames and \(plan.moveCount) moves. A file renamed and moved counts once. Completed changes support best-effort undo; nothing will be overwritten."
        )
      }
    }
    .alert("Permanently clear undo history?", isPresented: $confirmsClear) {
      Button("Cancel", role: .cancel) {}
      Button("Clear History and Lose Undo", role: .destructive) { model.clearHistory() }
    } message: {
      Text(
        "Tidy will forget retained task and file recovery records, including interrupted changes. You will lose the ability to undo those changes with Tidy. This does not reverse changes or edit, move, or delete user files. Folder grants and models are kept."
      )
    }
    .sheet(isPresented: $showsResults) {
      TaskResultsView(result: model.result, feedback: model.feedback)
    }
  }

  private var organize: some View {
    WorkspacePane {
      inventory
    } activity: {
      WorkspaceActivity(model: model, showsResults: $showsResults)
    } composer: {
      if model.inventory != nil {
        Divider()
        TaskComposerView(model: model, modelReady: setup.state == .ready, geometry: geometry)
          .padding(20)
      }
    }
  }

  private var inventory: some View {
    VStack(spacing: 0) {
      if let inventory = model.inventory {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 4) {
            Text(inventory.folder.path).font(.callout).textSelection(.enabled)
              .lineLimit(2).truncationMode(.middle).help(inventory.folder.path)
            Text(
              "\(inventory.candidateFiles.count) eligible files · \(inventory.skippedItems.count) skipped"
            )
            .font(.caption).foregroundStyle(.secondary)
            .accessibilityIdentifier("inventory-counts")
          }
          Spacer(minLength: 12)
          Text(model.accessDescription).font(.caption).foregroundStyle(.secondary)
            .multilineTextAlignment(.trailing).frame(maxWidth: 220, alignment: .trailing)
        }.padding(.horizontal, 20).padding(.vertical, 12)
          .accessibilityElement(children: .contain)
          .accessibilityIdentifier("workspace-folder-metadata")
          .background(WorkspaceRegion(name: "workspace-folder-metadata", geometry: geometry))

        if inventory.items.isEmpty {
          ContentUnavailableView(
            "This folder is empty", systemImage: "folder",
            description: Text("No files were changed. Choose another folder to organize."))
        } else {
          Table(filteredItems(inventory), selection: $selectedFiles) {
            TableColumn("Name") { item in
              Label(item.name, systemImage: item.skipReason == .folder ? "folder" : "doc")
                .lineLimit(1).truncationMode(.middle).help(item.name)
            }.width(min: 150, ideal: 320)
            TableColumn("Status") { item in
              Text(item.skipReason?.explanation ?? "Eligible")
                .lineLimit(1).help(item.skipReason?.explanation ?? "Eligible for metadata tasks")
            }.width(min: 100, ideal: 180)
            TableColumn("Size") { item in
              Text(
                item.byteCount.map {
                  ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
                } ?? "—")
            }.width(75)
          }
          .frame(minHeight: 0, maxHeight: .infinity)
          .searchable(text: $query, prompt: "Filter files")
          .accessibilityIdentifier("workspace-file-table")
          .background(WorkspaceRegion(name: "workspace-file-table", geometry: geometry))
        }
      } else if model.phase == .inspecting {
        ProgressView("Inspecting folder…").frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ContentUnavailableView {
          if let image = NSImage(named: NSImage.Name("Tidy")) {
            Image(nsImage: image).resizable().frame(width: 96, height: 96)
          } else {
            Label("Choose a folder", systemImage: "folder")
          }
          Text("A tidy folder starts here")
        } description: {
          Text("Choose the folder you’d like to inspect. You decide what Tidy can change.")
        } actions: {
          Button("Choose Folder…") { FolderPicker.choose(for: model) }
            .buttonStyle(.borderedProminent).disabled(model.isBusy)
        }
      }
    }.frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
  }

  private var readiness: String {
    if setup.state == .ready { return "Ready on this Mac" }
    if setup.isBusy { return "Setting up local model…" }
    if case .failed = setup.state { return "Model needs attention" }
    if case .unavailable = setup.state { return "Model unavailable" }
    return "Setup Required"
  }

  private func filteredItems(_ inventory: FolderInventory) -> [InventoryItem] {
    query.isEmpty
      ? inventory.items : inventory.items.filter { $0.name.localizedCaseInsensitiveContains(query) }
  }
}

enum FolderPicker {
  @MainActor static func choose(
    for model: WorkspaceModel, forWriting: Bool = false, initialFolder: URL? = nil
  ) {
    guard !model.isBusy else { return }
    let panel = NSOpenPanel()
    panel.title = forWriting ? "Select a folder to organize" : "Select a folder to inspect"
    panel.prompt = forWriting ? "Grant Write Access" : "Grant Read Access"
    panel.message =
      forWriting
      ? "Allow Tidy to rename and move files, create sorting folders here, and undo its changes. Only this folder is authorized."
      : "Tidy reads direct-child names and metadata. This does not authorize sorting or undo."
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = false
    panel.resolvesAliases = false
    panel.treatsFilePackagesAsDirectories = false
    panel.directoryURL = initialFolder ?? model.inventory?.folder
    if panel.runModal() == .OK, let folder = panel.url {
      model.inspect(folder, forWriting: forWriting)
    }
  }
}

struct WorkspaceCommands: Commands {
  let model: WorkspaceModel

  var body: some Commands {
    CommandGroup(replacing: .newItem) {
      Button("Choose Folder…") { FolderPicker.choose(for: model) }
        .keyboardShortcut("o").disabled(model.isBusy)
      Button("Grant Write Access…") { FolderPicker.choose(for: model, forWriting: true) }
        .disabled(model.isBusy)
    }
    CommandGroup(after: .sidebar) {
      Button("Organize") { model.destination = .organize }.keyboardShortcut("1")
      Button("History") { model.destination = .history }.keyboardShortcut("2")
    }
    CommandMenu("Task") {
      Button("Organize Files") { model.submit() }.keyboardShortcut(.return, modifiers: .command)
        .disabled(!model.canSubmit)
      Button("Cancel Task") { model.cancel() }.keyboardShortcut(".")
        .disabled(!model.canCancel)
    }
  }
}

extension SkipReason {
  var explanation: String {
    switch self {
    case .hidden: "Skipped · hidden item"
    case .package: "Skipped · app bundle or package"
    case .link: "Skipped · link or alias"
    case .incompleteDownload: "Skipped · incomplete download"
    case .cloudOnly: "Skipped · cloud-only; not downloaded"
    case .folder: "Skipped · existing folder"
    case .unsupportedFile: "Skipped · not an ordinary file"
    case .unavailable: "Skipped · metadata unavailable or access denied"
    }
  }
}
