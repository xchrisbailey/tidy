import AppKit
import SwiftUI
import TidyCore
import UniformTypeIdentifiers

struct DiagnosticsView: View {
  let coordinator: TaskCoordinator
  @State private var feedback: String?
  @State private var saving = false

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Private diagnostics").font(.title)
      Text("Save troubleshooting information for model, task and recovery failures on this Mac.")
      Text(
        "Includes only fixed diagnostic codes, counts and macOS version numbers. Excludes paths, filenames, requests, document contents and error messages, including nested errors."
      )
      Text(
        "Failure counts cover this app session. Retained history contributes only state counts. No diagnostic log is kept. Nothing is sent automatically: no telemetry, analytics, crash reporting or support submission."
      )
      .font(.callout).foregroundStyle(.secondary)
      Text(
        "Save locally if you want to keep it private. A location managed by your sync service may sync the exported file."
      )
      .font(.callout)
      Button("Save Diagnostics…") { save() }
        .disabled(saving)
        .accessibilityIdentifier("save-private-diagnostics")
      if let feedback {
        Text(feedback).textSelection(.enabled).accessibilityIdentifier("diagnostic-feedback")
      }
      Spacer()
    }
    .padding(24)
    .frame(minWidth: 520, minHeight: 350)
  }

  private func save() {
    let panel = NSSavePanel()
    panel.title = "Save private diagnostics"
    panel.nameFieldStringValue = "Tidy-diagnostics.json"
    panel.allowedContentTypes = [.json]
    panel.message =
      "Save a local file. Tidy will not transmit it or include private file information."
    guard panel.runModal() == .OK, let destination = panel.url else {
      feedback = "Export cancelled. Nothing was saved or sent."
      return
    }
    saving = true
    Task {
      defer { saving = false }
      // Model setup reasons are not diagnostic input; map only the closed state category.
      let modelState: DiagnosticModelState
      switch ModelServices.shared.setup.state {
      case .failed: modelState = .failed
      case .unavailable: modelState = .unavailable
      case .ready: modelState = .ready
      case .paused: modelState = .paused
      case .cancelled: modelState = .cancelled
      case .checkingSpace, .downloading, .verifying, .loading: modelState = .busy
      case .awaitingConsent: modelState = .notReady
      }
      do {
        try await coordinator.exportDiagnostics(to: destination, modelState: modelState)
        feedback = "Diagnostics saved. Nothing was sent. You choose whether to share this file."
      } catch {
        feedback = DiagnosticExportError.couldNotSave.localizedDescription
      }
    }
  }
}

struct DiagnosticsCommands: Commands {
  @Environment(\.openWindow) private var openWindow
  var body: some Commands {
    CommandGroup(after: .help) {
      Button("Private Diagnostics…") { openWindow(id: "diagnostics") }
    }
  }
}
