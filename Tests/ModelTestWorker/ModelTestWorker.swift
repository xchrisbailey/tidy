import Darwin
import Foundation
import TidyModel

@main
struct ModelTestWorker {
  @MainActor static func main() async throws {
    guard CommandLine.arguments.count == 4,
      let url = URL(string: CommandLine.arguments[3])
    else { exit(2) }
    alarm(20)
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let mode = CommandLine.arguments[2]
    let first = ModelManifest(
      id: "fixture", revision: "fixture-v1", name: "Fixture 1",
      files: [
        .init(
          name: "config.json", bytes: 3,
          sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", url: url)
      ])
    let next = ModelManifest(
      id: "fixture", revision: "fixture-v2", name: "Fixture 2",
      files: [
        .init(
          name: "config.json", bytes: 1_000_000,
          sha256: "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0", url: url)
      ])
    if mode == "seed" {
      let directory = root.appendingPathComponent("fixture-v1")
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try Data("abc".utf8).write(to: directory.appendingPathComponent("config.json"))
      try Data("fixture-v1".utf8).write(to: root.appendingPathComponent("active-revision"))
    }
    let setup = ModelSetup(
      root: root, manifest: first, replacements: [next],
      transfer: FixtureTransfer(checkpoint: mode), runtime: FixtureRuntime(checkpoint: mode))
    await setup.restore()
    if mode == "low-space" {
      let available = try ModelStorage.availableSpace(root)
      let required = setup.requiredFreeBytes
      await setup.download(consent: true)
      guard available < required,
        setup.activity == .failed(ModelStorageError.space.localizedDescription),
        setup.activeManifest == nil, setup.installedModels.isEmpty, setup.partialModels.isEmpty
      else { throw FixtureFailure.unexpectedState }
      let report = StorageSnapshot(availableBytes: available, requiredBytes: required)
      try FileHandle.standardOutput.write(contentsOf: JSONEncoder().encode(report))
      return
    }
    if ["transfer", "loading", "selection"].contains(mode) {
      guard setup.state == .ready, setup.activeManifest?.revision == "fixture-v1" else {
        throw FixtureFailure.unexpectedState
      }
      await setup.replace(revision: "fixture-v2", consent: true)
      exit(3)
    }
    if mode == "remove" {
      let active = setup.activeManifest?.revision
      let installed = setup.installedModels.map(\.manifest.revision).sorted()
      for model in setup.catalog { await setup.remove(revision: model.revision, consent: false) }
      guard setup.activeManifest?.revision == active,
        setup.installedModels.map(\.manifest.revision).sorted() == installed
      else { throw FixtureFailure.unexpectedState }
      for model in setup.catalog where model.revision != active {
        await setup.remove(revision: model.revision, consent: true)
        guard setup.activeManifest?.revision == active, setup.state == .ready else {
          throw FixtureFailure.unexpectedState
        }
      }
      if let active { await setup.remove(revision: active, consent: true) }
      await setup.cancel(revision: "fixture-v2")
    }
    let ready = setup.state == .ready
    let report = Snapshot(
      ready: ready, active: setup.activeManifest?.revision,
      installed: setup.installedModels.map(\.manifest.revision).sorted(),
      partials: setup.partialModels.map(\.manifest.revision).sorted())
    try FileHandle.standardOutput.write(contentsOf: JSONEncoder().encode(report))
  }
}

private struct StorageSnapshot: Encodable {
  let availableBytes: Int64
  let requiredBytes: Int64
}

private struct Snapshot: Encodable {
  let ready: Bool
  let active: String?
  let installed: [String]
  let partials: [String]
}

private enum FixtureFailure: Error { case unexpectedState }

private func terminateAtCheckpoint() -> Never {
  kill(getpid(), SIGKILL)
  while true { pause() }
}

private struct FixtureTransfer: ModelTransfer {
  let checkpoint: String

  func download(_ file: ModelFile, to destination: URL, resumeFile: URL) async throws {
    try await download(file, to: destination, resumeFile: resumeFile, progress: { _ in })
  }

  func download(
    _ file: ModelFile, to destination: URL, resumeFile: URL,
    progress: @escaping @Sendable (Int64) async -> Void
  ) async throws {
    try await URLSessionModelTransfer(allowLoopbackHTTP: true).download(
      file, to: destination, resumeFile: resumeFile
    ) { bytes in
      if checkpoint == "transfer", bytes > 0 { terminateAtCheckpoint() }
      await progress(bytes)
    }
  }

  func discardPartials(in directory: URL) async throws {
    try await URLSessionModelTransfer().discardPartials(in: directory)
  }
}

private actor FixtureRuntime: LocalModelRuntime {
  let checkpoint: String

  init(checkpoint: String) { self.checkpoint = checkpoint }

  func loadAndCheck(directory: URL, commit: @Sendable () throws -> Void) async throws {
    if directory.lastPathComponent == "fixture-v2", checkpoint == "loading" {
      terminateAtCheckpoint()
    }
    try commit()
    if directory.lastPathComponent == "fixture-v2", checkpoint == "selection" {
      terminateAtCheckpoint()
    }
  }

  func unload() async {}
}
