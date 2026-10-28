import SwiftUI
import TidyModel

struct ModelStorageView: View {
  let setup: ModelSetup
  @State private var removal: StoredModel?
  @State private var replacement: ModelManifest?

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Local Model Storage").font(.title)
      if let active = setup.activeManifest {
        Label("Ready offline · \(active.name)", systemImage: "checkmark.circle.fill")
        Text("Active revision: \(active.revision)").font(.caption.monospaced())
      } else {
        Text("No model is ready. Check an installed model offline or complete setup.")
      }
      List {
        Section("Installed versions") {
          ForEach(setup.installedModels) { model in
            HStack {
              version(model)
              Spacer()
              Text(model.id == setup.activeManifest?.revision ? "Active" : "Not active")
              Button("Remove…", role: .destructive) { removal = model }
                .disabled(setup.isBusy)
            }
          }
        }
        Section("Incomplete transfers · \(size(setup.partialBytes))") {
          ForEach(setup.partialModels) { model in
            HStack {
              version(model)
              Spacer()
              Button("Resume…") { replacement = model.manifest }
              Button("Remove Partials", role: .destructive) {
                Task { await setup.cancel(revision: model.id) }
              }
            }
            .disabled(setup.isBusy)
          }
        }
        Section("App-curated model") {
          ForEach(setup.catalog, id: \.revision) { model in
            if model.revision != setup.activeManifest?.revision {
              HStack {
                Text(model.name)
                Spacer()
                Button("Install / Replace…") { replacement = model }
                  .disabled(setup.isBusy)
              }
            }
          }
        }
      }
      if setup.activeManifest != nil {
        Text(
          "The working model stays ready until a verified replacement passes native inference. Old versions remain until you remove them."
        )
        .font(.callout)
      }
      activity
      HStack {
        Button("Refresh Storage") { setup.refreshStorage() }
        Button("Check Installed Model Offline") { Task { await setup.restore() } }
          .disabled(setup.isBusy)
        if setup.isBusy {
          Button("Pause") { Task { await setup.pause() } }
          Button("Cancel and Remove Partials") { Task { await setup.cancel() } }
        }
      }
    }
    .padding(24)
    .frame(minWidth: 680, minHeight: 500)
    .task {
      if setup.activeManifest == nil { await setup.restore() }
      setup.refreshStorage()
    }
    .alert(
      "Remove this model?",
      isPresented: Binding(
        get: { removal != nil }, set: { if !$0 { removal = nil } })
    ) {
      Button("Remove", role: .destructive) {
        if let removal { Task { await setup.remove(revision: removal.id, consent: true) } }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "Removing the active model disables local tasks until a model is checked or installed again. This deletes only Tidy’s model files."
      )
    }
    .alert(
      "Install this app-curated model?",
      isPresented: Binding(
        get: { replacement != nil }, set: { if !$0 { replacement = nil } })
    ) {
      Button("Agree and Install") {
        if let replacement {
          Task { await setup.replace(revision: replacement.revision, consent: true) }
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      if let replacement {
        Text(
          "\(replacement.name) · \(replacement.revision)\nDownload from Hugging Face: \(size(replacement.downloadBytes)). Storage is checked before downloading; the conservative reserve is \(size(replacement.downloadBytes * 3 + 512 * 1024 * 1024)). Existing verified files may be reused. No filenames or tasks are sent. The working model is retained on failure."
        )
      }
    }
  }

  private func version(_ model: StoredModel) -> some View {
    VStack(alignment: .leading) {
      Text(model.manifest.name)
      Text("\(model.id) · \(size(model.bytes)) stored files")
        .font(.caption.monospaced()).textSelection(.enabled)
    }
  }

  @ViewBuilder private var activity: some View {
    switch setup.activity {
    case .failed(let message), .unavailable(let message):
      Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
    case .paused: Text("Transfer paused. Resume requires consent; the current model is unchanged.")
    case .cancelled: Text("Cancelled. Partial data removed; the current model is unchanged.")
    case .downloading(_, let completed, let total):
      ProgressView("Downloading replacement…", value: Double(completed), total: Double(total))
    case .checkingSpace: ProgressView("Checking storage…")
    case .verifying: ProgressView("Verifying model files…")
    case .loading: ProgressView("Checking native inference before activation…")
    default: EmptyView()
    }
  }

  private func size(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }
}
