import Foundation
import Metal
import Observation

public struct ModelHardware: Sendable {
  public let appleSilicon: Bool
  public let memoryBytes: UInt64
  public let metalAvailable: Bool

  public init(appleSilicon: Bool, memoryBytes: UInt64, metalAvailable: Bool = true) {
    self.appleSilicon = appleSilicon
    self.memoryBytes = memoryBytes
    self.metalAvailable = metalAvailable
  }

  public static var current: Self {
    #if arch(arm64)
      Self(
        appleSilicon: true, memoryBytes: ProcessInfo.processInfo.physicalMemory,
        metalAvailable: MTLCreateSystemDefaultDevice() != nil)
    #else
      Self(appleSilicon: false, memoryBytes: ProcessInfo.processInfo.physicalMemory)
    #endif
  }

  public var unavailability: String? {
    if !appleSilicon { return "The local model requires an Apple silicon Mac." }
    if !metalAvailable { return "Metal GPU access is unavailable in this Mac session." }
    // This is a conservative experimental floor, not a release qualification claim.
    if memoryBytes < 16 << 30 {
      return "This candidate is not enabled on Macs with less than 16 GB of memory."
    }
    return nil
  }
}

public struct ModelFile: Sendable {
  public let name: String
  public let bytes: Int64
  public let sha256: String
  public let url: URL

  public init(name: String, bytes: Int64, sha256: String, url: URL) {
    self.name = name
    self.bytes = bytes
    self.sha256 = sha256
    self.url = url
  }
}

public struct ModelManifest: Sendable {
  public let id: String
  public let revision: String
  public let name: String
  public let files: [ModelFile]
  public var downloadBytes: Int64 { files.reduce(0) { $0 + $1.bytes } }

  public init(id: String, revision: String, name: String, files: [ModelFile]) {
    self.id = id
    self.revision = revision
    self.name = name
    self.files = files
  }
}

/// Returning (including throwing) guarantees no transfer writer can touch the destination again.
/// Cancellation may retain opaque URLSession resume data; explicit deletion follows quiescence.
public protocol ModelTransfer: Sendable {
  func download(_ file: ModelFile, to destination: URL, resumeFile: URL) async throws
  func download(
    _ file: ModelFile, to destination: URL, resumeFile: URL,
    progress: @escaping @Sendable (Int64) async -> Void
  ) async throws
  func discardPartials(in directory: URL) async throws
}

extension ModelTransfer {
  public func download(
    _ file: ModelFile, to destination: URL, resumeFile: URL,
    progress: @escaping @Sendable (Int64) async -> Void
  ) async throws {
    try await download(file, to: destination, resumeFile: resumeFile)
  }

  public func discardPartials(in directory: URL) async throws {}
}

public protocol LocalModelRuntime: Sendable {
  /// Commit only after verification/inference succeeds. Failure or cancellation must retain
  /// the previous working runtime; callers may continue using it during preparation.
  /// Check cancellation, call commit, then switch without suspension or further throwing work.
  func loadAndCheck(directory: URL, commit: @Sendable () throws -> Void) async throws
  func unload() async
}

extension LocalModelRuntime {
  public func loadAndCheck(directory: URL) async throws {
    try await loadAndCheck(directory: directory, commit: {})
  }
}

public enum ModelSetupState: Equatable, Sendable {
  case unavailable(String)
  case awaitingConsent
  case checkingSpace
  case downloading(file: String, completedBytes: Int64, totalBytes: Int64)
  case paused
  case verifying
  case loading
  case ready
  case failed(String)
  case cancelled
}

@Observable @MainActor
public final class ModelSetup {
  public var state: ModelSetupState { activeManifest == nil ? activity : .ready }
  public private(set) var activity: ModelSetupState
  public private(set) var activeManifest: ModelManifest?
  public private(set) var manifest: ModelManifest
  public let catalog: [ModelManifest]
  public private(set) var installedModels: [StoredModel] = []
  public private(set) var partialBytes: Int64 = 0
  public private(set) var partialModels: [StoredModel] = []
  public let root: URL
  private let hardware: ModelHardware
  private let transfer: any ModelTransfer
  private let runtime: any LocalModelRuntime
  private let availableSpace: @Sendable (URL) throws -> Int64
  private var operation: Task<Void, Never>?
  private var stopping = false

  public var modelDirectory: URL {
    root.appendingPathComponent(manifest.revision, isDirectory: true)
  }
  private var staging: URL {
    root.appendingPathComponent(manifest.revision + ".partial", isDirectory: true)
  }
  public var isBusy: Bool { operation != nil || stopping }
  public var requiredFreeBytes: Int64 { manifest.downloadBytes * 3 + 512 * 1024 * 1024 }

  public init(
    root: URL, manifest: ModelManifest, replacements: [ModelManifest] = [],
    hardware: ModelHardware = .current,
    transfer: any ModelTransfer, runtime: any LocalModelRuntime,
    availableSpace: @escaping @Sendable (URL) throws -> Int64 = ModelStorage.availableSpace
  ) {
    self.root = root
    self.manifest = manifest
    self.catalog = [manifest] + replacements.filter { $0.revision != manifest.revision }
    self.hardware = hardware
    self.transfer = transfer
    self.runtime = runtime
    self.availableSpace = availableSpace
    activity = hardware.unavailability.map(ModelSetupState.unavailable) ?? .awaitingConsent
    refreshStorage()
  }

  public func refreshStorage() {
    installedModels = catalog.compactMap { model in
      guard (try? ModelStorage.validate(model)) != nil else { return nil }
      let directory = root.appendingPathComponent(model.revision, isDirectory: true)
      guard FileManager.default.fileExists(atPath: directory.path) else { return nil }
      return StoredModel(manifest: model, bytes: ModelStorage.diskUsage(directory))
    }
    partialModels = catalog.compactMap { model in
      guard (try? ModelStorage.validate(model)) != nil else { return nil }
      let directory = root.appendingPathComponent(model.revision + ".partial", isDirectory: true)
      guard FileManager.default.fileExists(atPath: directory.path) else { return nil }
      return StoredModel(manifest: model, bytes: ModelStorage.diskUsage(directory))
    }
    partialBytes = partialModels.reduce(0) { $0 + $1.bytes }
  }

  public func replace(revision: String, consent: Bool) async {
    guard consent, !isBusy, hardware.unavailability == nil,
      revision != activeManifest?.revision,
      let candidate = catalog.first(where: { $0.revision == revision })
    else { return }
    manifest = candidate
    await perform(allowDownload: true)
  }

  public func remove(revision: String, consent: Bool) async {
    guard consent, !isBusy, let model = catalog.first(where: { $0.revision == revision })
    else { return }
    stopping = true
    defer {
      stopping = false
      refreshStorage()
    }
    do {
      try ModelStorage.validate(model)
      if revision == activeManifest?.revision {
        activity = .awaitingConsent
        activeManifest = nil
        await runtime.unload()
        try ModelStorage.removeIfPresent(selection)
      }
      try ModelStorage.removeIfPresent(root.appendingPathComponent(revision, isDirectory: true))
    } catch {
      activity = .failed("Model removal could not finish. Check storage permissions and retry.")
    }
  }

  private var selection: URL { root.appendingPathComponent("active-revision") }

  public func download(consent: Bool) async {
    guard hardware.unavailability == nil, consent, !isBusy,
      activeManifest?.revision != manifest.revision
    else { return }
    await perform(allowDownload: true)
  }

  /// A new lifecycle verifies installed files offline; passive windows share an already-ready runtime.
  public func restore() async {
    guard hardware.unavailability == nil, !isBusy, activeManifest == nil else { return }
    activity = .verifying
    if let revision = try? String(contentsOf: selection, encoding: .utf8),
      let selected = catalog.first(where: { $0.revision == revision })
    {
      manifest = selected
    }
    await perform(allowDownload: false)
  }

  public func pause() async {
    guard let operation, !stopping else { return }
    stopping = true
    operation.cancel()
    await operation.value
    if activeManifest == nil { await runtime.unload() }
    self.operation = nil
    activity = .paused
    stopping = false
  }

  public func cancel(revision: String? = nil) async {
    guard !stopping else { return }
    if let revision {
      guard !isBusy, let candidate = catalog.first(where: { $0.revision == revision }) else {
        return
      }
      manifest = candidate
    }
    stopping = true
    operation?.cancel()
    await operation?.value
    if activeManifest == nil { await runtime.unload() }
    do {
      try ModelStorage.validate(manifest)
      try await transfer.discardPartials(in: staging)
      try ModelStorage.removeIfPresent(staging)
      activity = .cancelled
    } catch {
      activity = .failed(
        "Cancelled, but partial-file cleanup failed. Retry Cancel before downloading again.")
    }
    operation = nil
    stopping = false
    refreshStorage()
  }

  private func perform(allowDownload: Bool) async {
    let task = Task { await run(allowDownload: allowDownload) }
    operation = task
    await withTaskCancellationHandler {
      await task.value
    } onCancel: {
      task.cancel()
    }
    operation = nil
    refreshStorage()
  }

  private func run(allowDownload: Bool) async {
    if activeManifest == nil { await runtime.unload() }
    do {
      try ModelStorage.validate(manifest)
      try Task.checkCancellation()
      if FileManager.default.fileExists(atPath: modelDirectory.path) {
        activity = .verifying
        do {
          try await ModelStorage.verify(manifest, directory: modelDirectory)
        } catch is CancellationError {
          throw CancellationError()
        } catch {
          guard allowDownload else { throw error }
          try ModelStorage.removeIfPresent(modelDirectory)
        }
      }
      if !FileManager.default.fileExists(atPath: modelDirectory.path) {
        guard allowDownload else {
          activity =
            FileManager.default.fileExists(atPath: staging.path) ? .paused : .awaitingConsent
          return
        }
        activity = .checkingSpace
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        guard try availableSpace(root) >= requiredFreeBytes,
          try availableSpace(FileManager.default.temporaryDirectory) >= requiredFreeBytes
        else { throw ModelStorageError.space }
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        var completed: Int64 = 0
        for file in manifest.files {
          try Task.checkCancellation()
          let destination = staging.appendingPathComponent(file.name)
          if !(try await ModelStorage.matches(file, at: destination)) {
            try ModelStorage.removeIfPresent(destination)
            activity = .downloading(
              file: file.name, completedBytes: completed, totalBytes: manifest.downloadBytes)
            let verifiedBytes = completed
            try await transfer.download(
              file, to: destination,
              resumeFile: staging.appendingPathComponent(file.name + ".resume")
            ) { [weak self] received in
              await self?.updateDownloadProgress(
                file: file, verifiedBytes: verifiedBytes, received: received)
            }
            try Task.checkCancellation()
            guard try await ModelStorage.matches(file, at: destination) else {
              try ModelStorage.removeIfPresent(destination)
              throw ModelStorageError.integrity
            }
          }
          try ModelStorage.removeIfPresent(staging.appendingPathComponent(file.name + ".resume"))
          completed += file.bytes
        }
        activity = .verifying
        try await ModelStorage.verify(manifest, directory: staging)
        try Task.checkCancellation()
        // Same-volume rename: an interrupted installation never becomes the installed directory.
        try FileManager.default.moveItem(at: staging, to: modelDirectory)
      }
      try Task.checkCancellation()
      activity = .loading
      let selection = selection
      let revision = manifest.revision
      // Native verification finishes before this atomic selection write. If the write
      // fails, the runtime must not switch. Relaunch never trusts this as a ready flag.
      try await runtime.loadAndCheck(directory: modelDirectory) {
        try Data(revision.utf8).write(to: selection, options: .atomic)
      }
      activeManifest = manifest
      activity = .ready
    } catch {
      if activeManifest == nil { await runtime.unload() }
      if Task.isCancelled {
        activity = .paused
      } else if let storageError = error as? ModelStorageError {
        activity = .failed(storageError.localizedDescription)
      } else {
        // Provider errors may contain signed URLs or content. Keep raw errors out of UI/logs.
        activity = .failed(
          "Setup could not finish. Check the connection or local runtime, then retry."
        )
      }
    }
  }

  private func updateDownloadProgress(file: ModelFile, verifiedBytes: Int64, received: Int64) {
    guard !stopping, case .downloading(let currentFile, _, _) = activity,
      currentFile == file.name
    else { return }
    activity = .downloading(
      file: file.name, completedBytes: verifiedBytes + min(file.bytes, max(0, received)),
      totalBytes: manifest.downloadBytes)
  }
}
