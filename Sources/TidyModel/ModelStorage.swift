import CryptoKit
import Foundation

public enum ModelStorageError: LocalizedError {
  case integrity
  case space
  case invalidManifest

  public var errorDescription: String? {
    switch self {
    case .integrity: "Model verification failed. Retry setup to replace missing or corrupt files."
    case .space:
      "Not enough free storage for the model, temporary transfer copies, and safety margin. Free space and retry."
    case .invalidManifest:
      "The bundled model manifest is invalid. Install a corrected version of Tidy."
    }
  }
}

public struct StoredModel: Sendable, Identifiable {
  public let manifest: ModelManifest
  public let bytes: Int64
  public var id: String { manifest.revision }
}

public enum ModelStorage {
  static func diskUsage(_ directory: URL) -> Int64 {
    guard
      let entries = FileManager.default.enumerator(
        at: directory, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
    else { return 0 }
    var bytes: Int64 = 0
    for case let url as URL in entries {
      if let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
        values.isRegularFile == true
      {
        bytes += Int64(values.fileSize ?? 0)
      }
    }
    return bytes
  }
  public static func availableSpace(_ directory: URL) throws -> Int64 {
    let values = try directory.resourceValues(forKeys: [
      .volumeAvailableCapacityForImportantUsageKey
    ])
    return values.volumeAvailableCapacityForImportantUsage ?? 0
  }

  static func validate(_ manifest: ModelManifest) throws {
    let names = manifest.files.map(\.name)
    let safe: (String) -> Bool = {
      !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("/") && !$0.contains("\\")
    }
    guard safe(manifest.revision), !names.isEmpty, Set(names).count == names.count,
      manifest.files.allSatisfy({
        safe($0.name) && !$0.name.hasSuffix(".resume") && $0.bytes > 0
          && $0.bytes < 10_000_000_000 && $0.sha256.count == 64
          && $0.sha256.allSatisfy({ "0123456789abcdef".contains($0) })
      }),
      manifest.files.count < 100
    else { throw ModelStorageError.invalidManifest }
  }

  static func removeIfPresent(_ url: URL) throws {
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
  }

  static func verify(_ manifest: ModelManifest, directory: URL) async throws {
    let values = try directory.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
    guard values.isSymbolicLink != true, values.isDirectory == true else {
      throw ModelStorageError.integrity
    }
    let allowed = Set(manifest.files.map(\.name))
    for entry in try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil)
    {
      guard allowed.contains(entry.lastPathComponent) else { throw ModelStorageError.integrity }
    }
    for file in manifest.files {
      guard try await matches(file, at: directory.appendingPathComponent(file.name)) else {
        throw ModelStorageError.integrity
      }
    }
  }

  static func matches(_ file: ModelFile, at url: URL) async throws -> Bool {
    let worker = Task.detached(priority: .utility) {
      guard FileManager.default.fileExists(atPath: url.path) else { return false }
      let values = try url.resourceValues(forKeys: [
        .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey,
      ])
      guard values.isSymbolicLink != true, values.isRegularFile == true,
        let size = values.fileSize, Int64(size) == file.bytes
      else { return false }
      let handle = try FileHandle(forReadingFrom: url)
      defer { try? handle.close() }
      var hash = SHA256()
      while true {
        try Task.checkCancellation()
        let chunk = try handle.read(upToCount: 1024 * 1024) ?? Data()
        if chunk.isEmpty { break }
        hash.update(data: chunk)
      }
      return hash.finalize().map { String(format: "%02x", $0) }.joined() == file.sha256
    }
    return try await withTaskCancellationHandler {
      try await worker.value
    } onCancel: {
      worker.cancel()
    }
  }
}
