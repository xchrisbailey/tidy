import Darwin
import Foundation
import TidyCore

@main
struct ProviderTestWorker {
  static func main() async throws {
    guard CommandLine.arguments.count == 4 else { exit(2) }
    alarm(30)
    let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let settings = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
    let mode = CommandLine.arguments[3]
    let coordinator = TaskCoordinator(
      bookmarkFile: settings.appendingPathComponent("folder.bookmark"))
    let inventory: FolderInventory
    if mode == "select" {
      inventory = try await coordinator.selectFolderForWriting(folder)
    } else if mode == "restore", let restored = try await coordinator.restoreFolder() {
      inventory = restored
    } else {
      throw ProviderFailure.unexpectedState
    }
    guard inventory.folder.standardizedFileURL == folder.standardizedFileURL else {
      throw ProviderFailure.unexpectedState
    }
    try check(inventory)
    // Restoration is the refresh path used by the workspace, not a cached inventory read.
    guard let refreshed = try await coordinator.restoreFolder() else {
      throw ProviderFailure.unexpectedState
    }
    try check(refreshed)
    let request = "Sort by type including subfolders"
    let response: [String: Any] = [
      "status": "plan", "message": "",
      "clauses": [["text": request, "effect": "sort"]],
      "sort": ["kind": "type", "evidence": request, "value": ""],
      "rename": [[String: String]](),
      "selection": ["extensions": [String](), "nameContains": "", "evidence": ""],
      "files": [
        ["sourceID": "f0", "disposition": "apply"],
        ["sourceID": "f1", "disposition": "apply"],
      ],
    ]
    let json = String(decoding: try JSONSerialization.data(withJSONObject: response), as: UTF8.self)
    let outcome = try await coordinator.planTask(request: request, model: { _, _, _ in json })
    guard case .plan(let plan) = outcome,
      plan.changes.map(\.originalName).sorted() == [
        "Nested/nested-downloaded.txt", "downloaded.txt",
      ],
      plan.skipped.contains(where: { $0.name == "cloud-only.txt" && $0.explanation == "cloudOnly" }
      ),
      plan.skipped.contains(where: {
        $0.name == "Nested/nested-cloud-only.txt" && $0.explanation == "cloudOnly"
      })
    else { throw ProviderFailure.unexpectedState }
    // Planning exercises recursive traversal without executing any file moves in iCloud.
    print(
      "PASS: \(mode), refresh and recursive plan; only two downloaded files eligible; both placeholders skipped"
    )
  }

  private static func check(_ inventory: FolderInventory) throws {
    guard inventory.items.first(where: { $0.name == "cloud-only.txt" })?.skipReason == .cloudOnly,
      inventory.candidateFiles.map(\.name) == ["downloaded.txt"]
    else { throw ProviderFailure.unexpectedState }
  }
}

private enum ProviderFailure: Error { case unexpectedState }
