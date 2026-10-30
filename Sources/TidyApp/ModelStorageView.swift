import SwiftUI
import TidyModel

struct ModelStorageView: View {
  let setup: ModelSetup
  let workspaceIsBusy: @MainActor () -> Bool
  @State private var removal: StoredModel?
  @State private var replacement: ModelManifest?
  @State private var removesPartials: StoredModel?

  var body: some View {
    Section("Model Storage") {
      if setup.installedModels.isEmpty { Text("No installed model").foregroundStyle(.secondary) }
      ForEach(setup.installedModels) { model in
        HStack(alignment: .top) {
          version(model)
          Spacer()
          if model.id == setup.activeManifest?.revision {
            Text("Active").foregroundStyle(.secondary)
          }
          Button("Remove…", role: .destructive) { removal = model }
            .disabled(setup.isBusy || workspaceIsBusy())
        }
      }
      if !setup.partialModels.isEmpty {
        DisclosureGroup("Incomplete Transfers · \(size(setup.partialBytes))") {
          ForEach(setup.partialModels) { model in
            HStack(alignment: .top) {
              version(model)
              Spacer()
              Button("Resume…") { replacement = model.manifest }
              Button("Remove…", role: .destructive) { removesPartials = model }
            }.disabled(setup.isBusy || workspaceIsBusy())
          }
        }
      }
      DisclosureGroup("App-Curated Versions") {
        ForEach(setup.catalog, id: \.revision) { model in
          if model.revision != setup.activeManifest?.revision {
            HStack {
              Text(model.name)
              Spacer()
              Button("Install…") { replacement = model }
                .disabled(setup.isBusy || workspaceIsBusy())
            }
          }
        }
        Text(
          "The working model stays ready until a verified replacement passes native inference. Old versions remain until you remove them."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      Button("Refresh Storage") { setup.refreshStorage() }.disabled(
        setup.isBusy || workspaceIsBusy())
    }
    .alert(
      "Remove this model?",
      isPresented: Binding(
        get: { removal != nil }, set: { if !$0 { removal = nil } }), presenting: removal
    ) {
      model in
      Button("Remove Model", role: .destructive) {
        Task {
          guard !workspaceIsBusy() else { return }
          await setup.remove(revision: model.id, consent: true)
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: { _ in
      Text(
        "Removing the active model disables local tasks until a model is checked or installed again. This deletes only Tidy’s model files."
      )
    }
    .alert(
      "Install this app-curated model?",
      isPresented: Binding(
        get: { replacement != nil }, set: { if !$0 { replacement = nil } }), presenting: replacement
    ) {
      model in
      Button("Agree and Install") {
        Task {
          guard !workspaceIsBusy() else { return }
          await setup.replace(revision: model.revision, consent: true)
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: { model in
      Text(
        "\(model.name)\nDownload from Hugging Face: \(size(model.downloadBytes)). Reserve \(size(model.downloadBytes * 3 + 512 * 1024 * 1024)) during setup. Verified files may be reused. No filenames or tasks are sent. The working model is retained on failure."
      )
    }
    .alert(
      "Remove incomplete download?",
      isPresented: Binding(
        get: { removesPartials != nil }, set: { if !$0 { removesPartials = nil } }),
      presenting: removesPartials
    ) {
      model in
      Button("Remove Partials", role: .destructive) {
        Task {
          guard !workspaceIsBusy() else { return }
          await setup.cancel(revision: model.id)
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: { _ in
      Text("This removes only the incomplete transfer. Installed model files are kept.")
    }
  }

  private func version(_ model: StoredModel) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(model.manifest.name)
      Text(size(model.bytes)).font(.caption).foregroundStyle(.secondary)
      DisclosureGroup("Revision") {
        Text(model.id).font(.caption.monospaced()).textSelection(.enabled)
      }
    }
  }

  private func size(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }
}
