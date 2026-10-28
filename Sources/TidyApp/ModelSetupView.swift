import SwiftUI
import TidyModel
import TidyModelRuntime

@MainActor
final class ModelServices {
  static let shared = ModelServices()
  let runtime: MLXLocalModelRuntime
  let setup: ModelSetup

  private init() {
    let runtime = MLXLocalModelRuntime()
    self.runtime = runtime
    setup = ModelSetup(
      root: URL.applicationSupportDirectory.appendingPathComponent(
        "Tidy/Models", isDirectory: true),
      manifest: .qwenCandidate, transfer: URLSessionModelTransfer(), runtime: runtime)
  }
}

struct ModelSetupScene: Scene {
  var body: some Scene {
    Window("Local Model Setup", id: "local-model") {
      ModelSetupView(setup: ModelServices.shared.setup)
    }
    .defaultSize(width: 620, height: 540)
    .commands { ModelSetupCommands() }
    Window("Local Model Storage", id: "model-storage") {
      ModelStorageView(setup: ModelServices.shared.setup)
    }
    .defaultSize(width: 760, height: 560)
  }
}

private struct ModelSetupCommands: Commands {
  @Environment(\.openWindow) private var openWindow
  var body: some Commands {
    CommandGroup(after: .appSettings) {
      Button("Local Model Setup…") { openWindow(id: "local-model") }
      Button("Local Model Storage…") { openWindow(id: "model-storage") }
    }
  }
}

struct ModelSetupView: View {
  let setup: ModelSetup
  @State private var consent = false

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Set up the local model").font(.title)
      Text(setup.manifest.name).font(.headline)
      Text("One curated candidate · MLX Swift · Apache-2.0 model · No account required")
        .font(.callout).foregroundStyle(.secondary)
      Text(
        "Download: \(size(setup.manifest.downloadBytes)). Keep at least \(size(setup.requiredFreeBytes)) free for setup, temporary copies, and a safety margin."
      )
      Text(
        "Apple silicon required. This candidate is provisionally enabled from 16 GB memory; that is not release hardware qualification. Lower-memory Macs and macOS 14 still need native verification. This Mac has \(size(Int64(ProcessInfo.processInfo.physicalMemory))) memory."
      )
      .font(.callout).foregroundStyle(.secondary)
      Divider()
      status
      Toggle(
        "I agree to download this model from Hugging Face into Tidy’s own storage.", isOn: $consent
      )
      .disabled(setup.isBusy || setup.state == .ready)
      Text(
        "Only setup uses the network. File names, requests, and model output are not sent to the provider. Tasks use the installed model locally. No cloud or Apple built-in model fallback."
      )
      .font(.callout)
      HStack {
        Button("Download / Resume") { Task { await setup.download(consent: consent) } }
          .disabled(!consent || setup.isBusy || setup.state == .ready || isUnavailable)
        if setup.isBusy {
          Button("Pause") { Task { await setup.pause() } }
        }
        Button("Cancel and Remove Partials") { Task { await setup.cancel() } }
          .disabled(isUnavailable)
      }
      Button("Check Installed Model Offline") { Task { await setup.restore() } }
        .disabled(setup.isBusy || isUnavailable)
      Text(
        "Interrupted transfers keep verified files and resume data when available. Resume may restart the current file if the system cannot resume it. Cancel waits for transfers to stop before removing partials; installed files are retained."
      )
      .font(.caption).foregroundStyle(.secondary)
      Text(
        "Weights: mlx-community/Qwen3-4B-Instruct-2507-4bit\nRevision: \(setup.manifest.revision)"
      )
      .font(.caption.monospaced()).textSelection(.enabled)
      Spacer(minLength: 0)
    }
    .padding(24)
    .frame(minWidth: 600, minHeight: 540)
    .task { await setup.restore() }
    .onDisappear {
      if setup.isBusy { Task { await setup.pause() } }
    }
  }

  @ViewBuilder private var status: some View {
    switch setup.state {
    case .awaitingConsent:
      Text("Not installed. Nothing downloads until you consent and choose Download.")
    case .unavailable(let reason):
      Label(reason, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
    case .checkingSpace:
      ProgressView("Checking storage…")
    case .downloading(let file, let completed, let total):
      ProgressView(value: Double(completed), total: Double(total)) {
        Text("Downloading \(file)… \(size(completed)) of \(size(total)) verified")
      }
      Text("Progress advances when each file finishes and verifies.").font(.caption)
    case .verifying:
      ProgressView("Verifying every file’s size and SHA-256…")
    case .loading:
      ProgressView("Loading locally and checking native inference…")
    case .paused:
      Text("Paused or interrupted. Consent and choose Resume to continue; no model is ready yet.")
    case .ready:
      Label("Offline inference ready on this Mac", systemImage: "checkmark.circle.fill")
        .foregroundStyle(.green)
      Text(
        "Integrity and a small inference check passed. File-planning quality and release hardware qualification are separate gates."
      )
      .font(.caption)
    case .failed(let reason):
      Label(reason, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
    case .cancelled:
      Text(
        "Cancelled. Partial downloads removed. No model is marked ready; installed files, if any, can be checked offline."
      )
    }
  }

  private var isUnavailable: Bool {
    if case .unavailable = setup.state { true } else { false }
  }

  private func size(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }
}
