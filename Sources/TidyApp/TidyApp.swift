import SwiftUI
import TidyCore
import TidyModelRuntime

@main
struct TidyApp: App {
  @State private var workspace: WorkspaceModel

  init() {
    let services = ModelServices.shared
    let coordinator = TaskCoordinator(
      bookmarkFile: URL.applicationSupportDirectory
        .appendingPathComponent("Tidy", isDirectory: true)
        .appendingPathComponent("selected-folder.bookmark"))
    _workspace = State(
      initialValue: WorkspaceModel(
        coordinator: coordinator, modelIsReady: { services.setup.state == .ready },
        completion: { system, user, limit in
          do {
            return try await services.runtime.completeJSON(
              system: system, user: user, maximumOutputTokens: limit)
          } catch LocalInferenceError.contextLimit {
            throw PlanningError.requestTooLarge
          } catch LocalInferenceError.outputLimit {
            throw PlanningError.requestTooLarge
          }
        }))
  }

  var body: some Scene {
    Window("Tidy", id: "inventory") {
      WorkspaceView(model: workspace, setup: ModelServices.shared.setup)
    }
    .defaultSize(width: 1080, height: 720)
    .windowToolbarStyle(.unified)
    .commands { WorkspaceCommands(model: workspace) }

    Settings {
      TidySettingsView(setup: ModelServices.shared.setup, workspaceIsBusy: { workspace.isBusy })
    }

    Window("Private Diagnostics", id: "diagnostics") {
      DiagnosticsView(coordinator: workspace.coordinator)
    }
    .defaultSize(width: 580, height: 420)
    .commands { DiagnosticsCommands() }
  }
}
