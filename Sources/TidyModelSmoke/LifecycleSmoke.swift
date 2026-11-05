import Darwin
import Foundation
import TidyModel
import TidyModelRuntime

extension ModelSmoke {
  @MainActor static func modelLifecycleWorker() async throws {
    guard let path = ProcessInfo.processInfo.environment["TIDY_LIFECYCLE_ROOT"],
      let checkpoint = ProcessInfo.processInfo.environment["TIDY_LIFECYCLE_CHECKPOINT"],
      ["restore", "before-selection", "after-selection"].contains(checkpoint)
    else { throw LocalInferenceError.smokeCheckFailed }
    let root = URL(fileURLWithPath: path, isDirectory: true).resolvingSymlinksInPath()
    guard
      try String(
        contentsOf: root.appendingPathComponent(".tidy-lifecycle-fixture"), encoding: .utf8)
        == "owned same-artifact lifecycle fixture\n"
    else { throw LocalInferenceError.smokeCheckFailed }
    try requireOfflineNetworkDenial()
    let original = ModelManifest.qwenCandidate
    let alias = ModelManifest(
      id: original.id, revision: original.revision + "-qualification", name: original.name,
      files: original.files)
    let runtime = MLXLocalModelRuntime()
    let setup = ModelSetup(
      root: root, manifest: original, replacements: [alias], transfer: NoLifecycleTransfer(),
      runtime: LifecycleRuntime(runtime: runtime, checkpoint: checkpoint, alias: alias.revision))
    await setup.restore()
    let expected = try String(
      contentsOf: root.appendingPathComponent("active-revision"), encoding: .utf8)
    guard setup.state == .ready, setup.activeManifest?.revision == expected else {
      throw LocalInferenceError.smokeCheckFailed
    }
    if checkpoint != "restore" {
      guard setup.activeManifest?.revision == original.revision else {
        throw LocalInferenceError.smokeCheckFailed
      }
      await setup.replace(revision: alias.revision, consent: true)
      throw LocalInferenceError.smokeCheckFailed
    }
    let result = try await runtime.completeJSON(
      system: "Return only JSON.", user: "Return exactly {\"status\":\"ready\"}.",
      maximumOutputTokens: 64)
    struct Ready: Decodable { let status: String }
    guard try JSONDecoder().decode(Ready.self, from: Data(result.utf8)).status == "ready" else {
      throw LocalInferenceError.smokeCheckFailed
    }
    print("LIFECYCLE restored verified artifact, fresh readiness and inference; no transfer")
    reportMemory("LIFECYCLE restored")
    await runtime.unload()
  }
}

private struct NoLifecycleTransfer: ModelTransfer {
  func download(_ file: ModelFile, to destination: URL, resumeFile: URL) async throws {
    throw LocalInferenceError.smokeCheckFailed
  }
}

private struct LifecycleRuntime: LocalModelRuntime {
  let runtime: MLXLocalModelRuntime
  let checkpoint: String
  let alias: String

  func loadAndCheck(directory: URL, commit: @Sendable () throws -> Void) async throws {
    try await runtime.loadAndCheck(directory: directory) {
      if directory.lastPathComponent == alias, checkpoint == "before-selection" {
        terminateAtLifecycleCheckpoint(checkpoint)
      }
      try commit()
      if directory.lastPathComponent == alias, checkpoint == "after-selection" {
        terminateAtLifecycleCheckpoint(checkpoint)
      }
    }
  }

  func unload() async { await runtime.unload() }
}

private func terminateAtLifecycleCheckpoint(_ checkpoint: String) -> Never {
  FileHandle.standardOutput.write(
    Data("LIFECYCLE verified native load checkpoint=\(checkpoint)\n".utf8))
  kill(getpid(), SIGKILL)
  while true { pause() }
}
