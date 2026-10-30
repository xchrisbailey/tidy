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

struct TidySettingsView: View {
  let setup: ModelSetup
  let workspaceIsBusy: @MainActor () -> Bool

  var body: some View {
    Form {
      if workspaceIsBusy() {
        Section {
          Label(
            "Model changes are unavailable while a file task is active. Existing downloads can still be paused or cancelled.",
            systemImage: "info.circle"
          )
          .font(.callout)
        }
      }
      ModelSetupView(setup: setup, workspaceIsBusy: workspaceIsBusy)
      ModelStorageView(setup: setup, workspaceIsBusy: workspaceIsBusy)
      Section("Privacy") {
        Text(
          "File names, contents, requests, and model output stay on this Mac. Only model setup uses the network. No account, telemetry, or cloud inference."
        )
        Text(
          "Changes in synced folders may be transmitted by your existing sync service. Diagnostics are saved locally only when you choose to export them from Help."
        )
        .font(.callout).foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .frame(width: 640, height: 640)
    .task {
      await setup.restore()
      setup.refreshStorage()
    }
  }
}

struct ModelSetupView: View {
  let setup: ModelSetup
  let workspaceIsBusy: @MainActor () -> Bool
  @State private var consent = false

  var body: some View {
    Section("Local Model") {
      LabeledContent("Model", value: setup.activeManifest?.name ?? setup.manifest.name)
      if setup.state == .ready {
        Label("Ready on this Mac", systemImage: "checkmark.circle")
      }
      ModelActivityView(state: setup.activity, hasActiveModel: setup.activeManifest != nil)
      if setup.activeManifest == nil {
        LabeledContent("Download", value: size(setup.manifest.downloadBytes))
        LabeledContent("Space needed during setup", value: size(setup.requiredFreeBytes))
        Toggle(
          "I agree to download this model from Hugging Face into Tidy’s storage", isOn: $consent
        )
        .disabled(setup.isBusy || workspaceIsBusy() || isUnavailable)
        if !setup.isBusy {
          Button(downloadTitle) {
            Task {
              guard !workspaceIsBusy() else { return }
              await setup.download(consent: consent)
            }
          }
          .disabled(!consent || workspaceIsBusy() || isUnavailable)
        }
      }
      if setup.isBusy {
        HStack {
          Button("Pause") { Task { await setup.pause() } }
          Button("Cancel and Remove Partials", role: .destructive) { Task { await setup.cancel() } }
        }
      }
      Button("Check Installed Model Offline") {
        Task {
          guard !workspaceIsBusy() else { return }
          await setup.restore()
        }
      }
      .disabled(setup.isBusy || workspaceIsBusy() || isUnavailable)
      Text(
        "Closing Settings does not pause a download. Use Pause or Cancel to stop it. Interrupted transfers retain verified files and resume data when available."
      )
      .font(.caption).foregroundStyle(.secondary)
      DisclosureGroup("Compatibility and Technical Details") {
        Text(
          "Apple silicon required. This candidate is provisionally enabled from 16 GB memory; this is not release hardware qualification. Lower-memory Macs and macOS 14 still need native verification."
        )
        Text(
          "Weights: mlx-community/Qwen3-4B-Instruct-2507-4bit\nRevision: \(setup.activeManifest?.revision ?? setup.manifest.revision)"
        )
        .font(.caption.monospaced()).textSelection(.enabled)
        Text(
          "One app-curated model · MLX Swift · Apache-2.0 model · No account required. Readiness requires integrity and native inference checks, not just received bytes. Pause and cancellation wait for transfers to stop before cleanup; installed files are retained."
        )
        .font(.caption)
      }
    }
  }

  private var isUnavailable: Bool {
    if case .unavailable = setup.activity { return true }
    return false
  }

  private var downloadTitle: String {
    switch setup.activity {
    case .paused: "Resume Download"
    case .failed: "Retry Download"
    default: "Download Model"
    }
  }

  private func size(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }
}

struct ModelActivityView: View {
  let state: ModelSetupState
  let hasActiveModel: Bool

  var body: some View {
    switch state {
    case .awaitingConsent:
      Text("Nothing downloads until you consent and choose Download.").foregroundStyle(.secondary)
    case .unavailable(let reason), .failed(let reason):
      Label(reason, systemImage: "exclamationmark.triangle").textSelection(.enabled)
    case .checkingSpace:
      ProgressView("Checking storage…")
    case .downloading(let file, let completed, let total):
      ProgressView(value: Double(completed), total: Double(max(1, total))) {
        Text(
          "\(hasActiveModel ? "Downloading replacement" : "Downloading") · \(size(completed)) of \(size(total))"
        )
      }
      Text(file).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        .help(file)
    case .verifying: ProgressView("Verifying model files…")
    case .loading: ProgressView("Checking local inference…")
    case .paused:
      Label("Download paused", systemImage: "pause.circle")
      if hasActiveModel { Text("Your working model is still ready.").font(.caption) }
    case .ready: EmptyView()
    case .cancelled:
      Label("Download cancelled · partial files removed", systemImage: "stop.circle")
      if hasActiveModel { Text("Your working model is unchanged.").font(.caption) }
    }
  }

  private func size(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }
}
