import AppKit
import CryptoKit
import Foundation
import SwiftUI
import Testing
import TidyCore
import TidyModel

@testable import TidyApp

@MainActor
struct WorkspaceGeometryTests {
  @Test func changingNativeSidebarDestinationsDoesNotCancelPlanning() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "tidy-navigation-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("Selected")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("navigation fixture".utf8).write(to: folder.appendingPathComponent("notes.txt"))
    let setup = try await layoutSetup(root: root)
    let gate = PlanningGate()
    let coordinator = TaskCoordinator(
      bookmarkFile: root.appendingPathComponent("settings/folder.bookmark"))
    let model = WorkspaceModel(
      coordinator: coordinator, modelIsReady: { true },
      completion: { _, _, _ in
        await gate.complete()
      })
    model.inspect(folder, forWriting: true)
    await model.waitUntilFinished()
    NSApplication.shared.setActivationPolicy(.prohibited)
    let window = NSWindow(
      contentRect: NSRect(x: -20000, y: -20000, width: 1080, height: 720),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: WorkspaceView(model: model, setup: setup))
    defer { window.close() }
    window.contentView?.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(100))
    model.submit()
    await gate.waitUntilStarted()
    model.destination = .history
    try await Task.sleep(for: .milliseconds(100))
    #expect(model.phase == .planning)
    model.destination = .organize
    try await Task.sleep(for: .milliseconds(100))
    #expect(model.phase == .planning)
    #expect(await gate.calls == 1)
    await gate.release()
    await model.waitUntilFinished()
    #expect(model.result?.changed.count == 1)
    #expect(
      FileManager.default.fileExists(
        atPath: folder.appendingPathComponent("Documents/notes.txt").path))
  }

  @Test func productionWorkspaceFitsNativeWindowChromeAndComposer() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "tidy-geometry-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("Downloads")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for index in 0..<30 {
      try Data("layout fixture".utf8).write(
        to: folder.appendingPathComponent("document-\(index).txt"))
    }
    let setup = try await layoutSetup(root: root)
    let coordinator = TaskCoordinator(
      bookmarkFile: root.appendingPathComponent("settings/folder.bookmark"))
    let model = WorkspaceModel(
      coordinator: coordinator, modelIsReady: { true },
      completion: { _, _, _ in
        "invalid fixture response"
      })
    model.inspect(folder)
    await model.waitUntilFinished()
    NSApplication.shared.setActivationPolicy(.prohibited)
    let window = NSWindow(
      contentRect: NSRect(x: -20000, y: -20000, width: 1080, height: 720),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.title = "Tidy — UI Verification Fixtures"
    window.toolbar = NSToolbar(identifier: "TidyGeometryToolbar")
    window.toolbarStyle = .unified
    let geometry = WorkspaceGeometry()
    window.contentView = NSHostingView(
      rootView: WorkspaceView(model: model, setup: setup, geometry: geometry))
    window.orderFront(nil)
    defer { window.close() }
    for appearance in [NSAppearance.Name.aqua, .darkAqua] {
      window.appearance = NSAppearance(named: appearance)
      for size in [NSSize(width: 1080, height: 720), NSSize(width: 900, height: 600)] {
        window.setContentSize(size)
        try await Task.sleep(for: .milliseconds(150))
        window.contentView?.layoutSubtreeIfNeeded()
        let frames = geometry.frames(in: window)
        let identifiers = [
          "workspace-nav-Organize", "workspace-nav-History",
          "workspace-folder-metadata", "workspace-file-table", "workspace-task-composer",
        ]
        for identifier in identifiers {
          let rect = try #require(frames[identifier], "Missing native region \(identifier)")
          #expect(
            rect.maxY <= window.contentLayoutRect.maxY + 1,
            "\(identifier) extends into the title bar at \(size), \(appearance)")
          #expect(
            rect.minY >= window.contentLayoutRect.minY - 1,
            "\(identifier) extends below the window at \(size), \(appearance)")
        }
        let table = try #require(frames["workspace-file-table"])
        let composer = try #require(frames["workspace-task-composer"])
        #expect(!table.intersects(composer), "The file table overlaps the composer")
        #expect(table.height > 100, "The file table needs usable vertical space")
        try snapshot(window, name: "\(appearance.rawValue)-\(Int(size.width))")
      }
    }
  }
}

@MainActor
private func snapshot(_ window: NSWindow, name: String) throws {
  guard let path = ProcessInfo.processInfo.environment["TIDY_WORKSPACE_SNAPSHOTS"],
    let view = window.contentView?.superview,
    let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
  else { return }
  view.cacheDisplay(in: view.bounds, to: bitmap)
  guard let data = bitmap.representation(using: .png, properties: [:]) else { return }
  let directory = URL(fileURLWithPath: path, isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  try data.write(to: directory.appendingPathComponent("\(name).png"))
}

@MainActor
private func layoutSetup(root: URL) async throws -> ModelSetup {
  let bytes = Data("LAYOUT MODEL FIXTURE".utf8)
  let manifest = ModelManifest(
    id: "fixture", revision: "layout-v1", name: "Local Model Fixture",
    files: [
      ModelFile(
        name: "weights.bin", bytes: Int64(bytes.count),
        sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
        url: URL(string: "https://example.invalid/fixture")!)
    ])
  let setup = ModelSetup(
    root: root.appendingPathComponent("Models"), manifest: manifest,
    hardware: ModelHardware(appleSilicon: true, memoryBytes: 16 << 30),
    transfer: LayoutTransfer(bytes: bytes), runtime: LayoutRuntime(),
    availableSpace: { _ in Int64.max })
  await setup.download(consent: true)
  return setup
}

private actor LayoutTransfer: ModelTransfer {
  let bytes: Data
  init(bytes: Data) { self.bytes = bytes }
  func download(_ file: ModelFile, to destination: URL, resumeFile: URL) async throws {
    try bytes.write(to: destination)
  }
}

private actor LayoutRuntime: LocalModelRuntime {
  func loadAndCheck(directory: URL, commit: @Sendable () throws -> Void) async throws {
    try commit()
  }
  func unload() async {}
}
