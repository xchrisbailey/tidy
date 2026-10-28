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
  func discardPartials(in directory: URL) async throws
}

extension ModelTransfer {
  public func discardPartials(in directory: URL) async throws {}
}

public protocol LocalModelRuntime: Sendable {
  func loadAndCheck(directory: URL) async throws
  func unload() async
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
  public private(set) var state: ModelSetupState
  public let manifest: ModelManifest
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
    root: URL, manifest: ModelManifest, hardware: ModelHardware = .current,
    transfer: any ModelTransfer, runtime: any LocalModelRuntime,
    availableSpace: @escaping @Sendable (URL) throws -> Int64 = ModelStorage.availableSpace
  ) {
    self.root = root
    self.manifest = manifest
    self.hardware = hardware
    self.transfer = transfer
    self.runtime = runtime
    self.availableSpace = availableSpace
    state = hardware.unavailability.map(ModelSetupState.unavailable) ?? .awaitingConsent
  }

  public func download(consent: Bool) async {
    guard hardware.unavailability == nil, consent, !isBusy else { return }
    await perform(allowDownload: true)
  }

  /// Restoring an installation never requests network access and never trusts cached readiness.
  public func restore() async {
    guard hardware.unavailability == nil, !isBusy else { return }
    await perform(allowDownload: false)
  }

  public func pause() async {
    guard let operation, !stopping else { return }
    stopping = true
    operation.cancel()
    await operation.value
    await runtime.unload()
    self.operation = nil
    state = .paused
    stopping = false
  }

  public func cancel() async {
    guard !stopping else { return }
    stopping = true
    operation?.cancel()
    await operation?.value
    await runtime.unload()
    do {
      try await transfer.discardPartials(in: staging)
      try ModelStorage.removeIfPresent(staging)
      state = .cancelled
    } catch {
      state = .failed(
        "Cancelled, but partial-file cleanup failed. Retry Cancel before downloading again.")
    }
    operation = nil
    stopping = false
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
  }

  private func run(allowDownload: Bool) async {
    await runtime.unload()
    do {
      try ModelStorage.validate(manifest)
      try Task.checkCancellation()
      if FileManager.default.fileExists(atPath: modelDirectory.path) {
        state = .verifying
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
          state = FileManager.default.fileExists(atPath: staging.path) ? .paused : .awaitingConsent
          return
        }
        state = .checkingSpace
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
            state = .downloading(
              file: file.name, completedBytes: completed, totalBytes: manifest.downloadBytes)
            try await transfer.download(
              file, to: destination,
              resumeFile: staging.appendingPathComponent(file.name + ".resume"))
            try Task.checkCancellation()
            guard try await ModelStorage.matches(file, at: destination) else {
              try ModelStorage.removeIfPresent(destination)
              throw ModelStorageError.integrity
            }
          }
          try ModelStorage.removeIfPresent(staging.appendingPathComponent(file.name + ".resume"))
          completed += file.bytes
        }
        state = .verifying
        try await ModelStorage.verify(manifest, directory: staging)
        try Task.checkCancellation()
        // Same-volume rename: an interrupted installation never becomes the installed directory.
        try FileManager.default.moveItem(at: staging, to: modelDirectory)
      }
      try Task.checkCancellation()
      state = .loading
      try await runtime.loadAndCheck(directory: modelDirectory)
      try Task.checkCancellation()
      state = .ready
    } catch {
      await runtime.unload()
      if Task.isCancelled {
        state = .paused
      } else if let storageError = error as? ModelStorageError {
        state = .failed(storageError.localizedDescription)
      } else {
        // Provider errors may contain signed URLs or content. Keep raw errors out of UI/logs.
        state = .failed(
          "Setup could not finish. Check the connection or local runtime, then retry. No model is ready."
        )
      }
    }
  }
}
