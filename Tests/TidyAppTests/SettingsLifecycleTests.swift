import AppKit
import CryptoKit
import Foundation
import SwiftUI
import Testing
import TidyModel

@testable import TidyApp

@MainActor
struct SettingsLifecycleTests {
  @Test func removingAndReopeningSettingsDoesNotPauseItsServiceOwnedDownload() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "tidy-settings-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let bytes = Data("LOCAL MODEL FIXTURE".utf8)
    let transfer = SettingsTransfer(bytes: bytes)
    let manifest = ModelManifest(
      id: "fixture", revision: "settings-v1", name: "Settings fixture",
      files: [
        ModelFile(
          name: "weights.bin", bytes: Int64(bytes.count),
          sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
          url: URL(string: "https://example.invalid/weights.bin")!)
      ])
    let setup = ModelSetup(
      root: root, manifest: manifest,
      hardware: ModelHardware(appleSilicon: true, memoryBytes: 16 << 30),
      transfer: transfer, runtime: SettingsRuntime(), availableSpace: { _ in Int64.max })
    let download = Task { await setup.download(consent: true) }
    await transfer.waitUntilStarted()
    NSApplication.shared.setActivationPolicy(.prohibited)
    let lifecycle = SettingsLifecycle()
    let window = NSWindow(
      contentRect: NSRect(x: -20000, y: -20000, width: 640, height: 640),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let view = TidySettingsView(setup: setup, workspaceIsBusy: { false })
      .onAppear { lifecycle.appeared = true }
      .onDisappear { lifecycle.disappeared = true }
    window.contentView = NSHostingView(rootView: view)
    window.contentView?.layoutSubtreeIfNeeded()
    for _ in 0..<100 where !lifecycle.appeared { try await Task.sleep(for: .milliseconds(10)) }
    #expect(lifecycle.appeared)
    window.contentView = nil
    for _ in 0..<100 where !lifecycle.disappeared { try await Task.sleep(for: .milliseconds(10)) }
    #expect(lifecycle.disappeared)
    #expect(setup.isBusy)
    #expect(await transfer.cancelled == false)
    window.contentView = NSHostingView(rootView: view)
    window.contentView?.layoutSubtreeIfNeeded()
    await setup.restore()
    #expect(setup.isBusy)
    #expect(await transfer.starts == 1)
    await transfer.finish()
    await download.value
    #expect(setup.state == .ready)
    #expect(setup.activeManifest?.revision == manifest.revision)
  }
}

@MainActor private final class SettingsLifecycle {
  var appeared = false
  var disappeared = false
}

private actor SettingsTransfer: ModelTransfer {
  let bytes: Data
  private var waiter: CheckedContinuation<Void, Never>?
  private var started: CheckedContinuation<Void, Never>?
  private(set) var starts = 0
  private(set) var cancelled = false

  init(bytes: Data) { self.bytes = bytes }

  func download(_ file: ModelFile, to destination: URL, resumeFile: URL) async throws {
    starts += 1
    started?.resume()
    started = nil
    await withTaskCancellationHandler {
      await withCheckedContinuation { waiter = $0 }
    } onCancel: {
      Task { await self.cancelTransfer() }
    }
    try Task.checkCancellation()
    try bytes.write(to: destination)
  }

  func waitUntilStarted() async {
    if starts > 0 { return }
    await withCheckedContinuation { started = $0 }
  }

  func finish() {
    waiter?.resume()
    waiter = nil
  }
  private func cancelTransfer() {
    cancelled = true
    finish()
  }
}

private actor SettingsRuntime: LocalModelRuntime {
  func loadAndCheck(directory: URL, commit: @Sendable () throws -> Void) async throws {
    try commit()
  }
  func unload() async {}
}
