import AppKit
import Foundation
import SwiftUI
import Testing
import TidyCore

@testable import TidyApp

@MainActor
struct WorkspaceUsabilityTests {
  @Test(arguments: [false, true])
  func longErrorDetailsRemainScrollableWithDoneButtonInsideWindow(refreshOnly: Bool) async throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let geometry = WorkspaceGeometry()
    let detail = String(
      repeating: "The selected folder is unavailable. Choose it again to grant access. ", count: 120
    )
    let window = NSWindow(
      contentRect: NSRect(x: -20000, y: -20000, width: 640, height: 510),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.contentView = NSHostingView(
      rootView: TaskResultsView(
        result: nil,
        feedback: refreshOnly
          ? nil : WorkspaceFeedback(kind: .failure, title: "Couldn’t finish", detail: detail),
        refreshError: refreshOnly ? detail : nil,
        geometry: geometry))
    try await Task.sleep(for: .milliseconds(100))
    window.contentView?.layoutSubtreeIfNeeded()
    let done = try #require(geometry.frames(in: window)["results-done"])
    #expect(done.minY >= window.contentLayoutRect.minY - 1)
    #expect(done.maxY <= window.contentLayoutRect.maxY + 1)
    let scrollViews = descendants(of: window.contentView).compactMap { $0 as? NSScrollView }
    #expect(
      scrollViews.contains { scroll in
        guard let document = scroll.documentView else { return false }
        return document.bounds.height > scroll.contentView.bounds.height
      }, "A long error must have a scrollable surface, not a clipped paragraph")
  }

  @Test func requestFieldAcceptsNativeKeyboardFocusAndEditing() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "tidy-keyboard-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let model = WorkspaceModel(
      coordinator: TaskCoordinator(bookmarkFile: root.appendingPathComponent("folder.bookmark")),
      modelIsReady: { true },
      completion: { _, _, _ in
        Issue.record("Keyboard editing must not execute a task")
        return ""
      })
    model.windowDidOpen()
    NSApplication.shared.setActivationPolicy(.prohibited)
    let window = NSWindow(
      contentRect: NSRect(x: -20000, y: -20000, width: 720, height: 280),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.contentView = NSHostingView(
      rootView: TaskComposerView(model: model, modelReady: true).padding(20))
    try await Task.sleep(for: .milliseconds(100))
    window.contentView?.layoutSubtreeIfNeeded()
    let inputs = descendants(of: window.contentView)
    let input = try #require(
      inputs.first { view in
        if let text = view as? NSTextView { return text.string == model.request && text.isEditable }
        if let field = view as? NSTextField {
          return field.stringValue == model.request && field.isEditable
        }
        return false
      }, "The request should expose a native editable text control")
    #expect(window.makeFirstResponder(input))
    let editor = try #require(window.firstResponder as? NSTextView)
    editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count))
    editor.insertText("Group by modification month", replacementRange: editor.selectedRange())
    try await Task.sleep(for: .milliseconds(50))
    #expect(model.request == "Group by modification month")
    #expect(!model.isBusy)
  }
}

@MainActor
private func descendants(of view: NSView?) -> [NSView] {
  guard let view else { return [] }
  return [view] + view.subviews.flatMap { descendants(of: $0) }
}
