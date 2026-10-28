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
  @State private var operation: Task<Void, Never>?

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        VStack(alignment: .leading) {
          Text("Folder inventory").font(.title)
          Text("Read-only • Direct children only").foregroundStyle(.secondary)
        }
        Spacer()
        Button("Select Folder…", action: selectFolder)
          .disabled(isInspecting)
        Button("Refresh") { inspect() }
          .disabled(isInspecting || inventory == nil)
      }

      Text(
        "Tidy inspects names and metadata locally. This inventory does not read file contents, download files, or change anything. It is not a plan preview."
      )
      .font(.callout)
      Text(
        "Already-downloaded files in synced folders can be eligible. If you organize them in a later version, your existing sync service may transmit those changes."
      )
      .font(.callout).foregroundStyle(.secondary)

      if isInspecting {
        HStack {
          ProgressView().controlSize(.small)
          Text("Inspecting folder…")
          Button("Cancel") { operation?.cancel() }
        }
      }
      if let errorMessage {
        Label(errorMessage, systemImage: "exclamationmark.triangle")
          .foregroundStyle(.orange)
          .textSelection(.enabled)
      }
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
    }
    .padding(24)
    .frame(minWidth: 720, minHeight: 480)
    .task { inspect() }
    .onDisappear { operation?.cancel() }
  }

  private func selectFolder() {
    let panel = NSOpenPanel()
    panel.title = "Select a folder to inspect"
    panel.prompt = "Grant Read Access"
    panel.message = "Tidy only inventories direct children. No files will be changed."
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = false
    panel.resolvesAliases = false
    panel.treatsFilePackagesAsDirectories = false
    if panel.runModal() == .OK, let folder = panel.url {
      inspect(folder)
    }
  }

  private func inspect(_ folder: URL? = nil) {
    guard !isInspecting else { return }
    isInspecting = true
    errorMessage = nil
    inventory = nil
    operation = Task {
      defer { isInspecting = false }
      do {
        if let folder {
          inventory = try await coordinator.selectFolder(folder)
        } else {
          inventory = try await coordinator.restoreFolder()
        }
      } catch is CancellationError {
        errorMessage = "Inventory cancelled. No files were changed."
      } catch {
        errorMessage = error.localizedDescription
      }
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
