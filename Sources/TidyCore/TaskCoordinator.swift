import Darwin
import Foundation

public struct InventoryItem: Sendable, Identifiable {
  public let name: String
  public var id: String { name }
  public let skipReason: SkipReason?
  public let byteCount: Int64?
  public let modificationDate: Date?
  var snapshot: FileSnapshot? = nil
}

public enum SkipReason: String, Sendable {
  case hidden, package, link, incompleteDownload, cloudOnly, folder, unsupportedFile, unavailable
}

public struct FolderInventory: Sendable {
  public let folder: URL
  public let items: [InventoryItem]

  public var candidateFiles: [InventoryItem] { items.filter { $0.skipReason == nil } }
  public var skippedItems: [InventoryItem] { items.filter { $0.skipReason != nil } }
}

public enum FolderAccessError: Error, LocalizedError, Equatable {
  case notFolder, accessUnavailable, savedGrantUnavailable, rememberingFailed

  public var errorDescription: String? {
    switch self {
    case .notFolder:
      "Choose an ordinary folder, not a link or app bundle."
    case .accessUnavailable:
      "This folder is unavailable or access was revoked. Select it again to grant access. Tidy has not inspected another location."
    case .savedGrantUnavailable:
      "The remembered folder grant is unavailable. Select a folder again to grant access."
    case .rememberingFailed:
      "Tidy could not remember this folder grant. No files were changed. Try selecting it again."
    }
  }
}

public actor TaskCoordinator {
  let bookmarkFile: URL
  var selectedInventory: FolderInventory?
  var selectedRootIdentity: FileIdentity?

  public init(bookmarkFile: URL) {
    self.bookmarkFile = bookmarkFile
  }

  public func restoreFolder() throws -> FolderInventory? {
    try Task.checkCancellation()
    guard FileManager.default.fileExists(atPath: bookmarkFile.path) else { return nil }
    let data: Data
    do {
      data = try Data(contentsOf: bookmarkFile)
    } catch {
      throw FolderAccessError.savedGrantUnavailable
    }
    return try inventory(bookmark: data, save: false)
  }

  public func selectFolder(_ folder: URL) throws -> FolderInventory {
    try Task.checkCancellation()
    let accessing = folder.startAccessingSecurityScopedResource()
    defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
    try validateFolder(folder)
    return try inventory(bookmark: makeBookmark(folder), save: true)
  }

  private func inventory(bookmark: Data, save: Bool) throws -> FolderInventory {
    var stale = false
    let folder: URL
    do {
      folder = try URL(
        resolvingBookmarkData: bookmark,
        options: [.withSecurityScope, .withoutUI, .withoutMounting], relativeTo: nil,
        bookmarkDataIsStale: &stale
      )
    } catch {
      throw FolderAccessError.savedGrantUnavailable
    }
    guard folder.startAccessingSecurityScopedResource() else {
      throw FolderAccessError.accessUnavailable
    }
    defer { folder.stopAccessingSecurityScopedResource() }
    try validateFolder(folder)
    let children: [URL]
    do {
      children = try FileManager.default.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: nil)
    } catch {
      throw FolderAccessError.accessUnavailable
    }
    let items = try children.map { child in
      try Task.checkCancellation()
      return inspect(child)
    }
    try Task.checkCancellation()
    if save || stale {
      try saveBookmark(stale ? makeBookmark(folder) : bookmark)
    }
    let result = FolderInventory(folder: folder, items: items.sorted { $0.name < $1.name })
    selectedInventory = result
    var rootInfo = stat()
    guard lstat(folder.path, &rootInfo) == 0 else { throw FolderAccessError.accessUnavailable }
    selectedRootIdentity = FileIdentity(rootInfo)
    return result
  }

  private func validateFolder(_ folder: URL) throws {
    var info = stat()
    guard lstat(folder.path, &info) == 0 else { throw FolderAccessError.accessUnavailable }
    guard info.st_mode & S_IFMT == S_IFDIR else { throw FolderAccessError.notFolder }
    do {
      let values = try folder.resourceValues(forKeys: [.isPackageKey, .isAliasFileKey])
      guard values.isPackage != true, values.isAliasFile != true else {
        throw FolderAccessError.notFolder
      }
    } catch let error as FolderAccessError {
      throw error
    } catch {
      throw FolderAccessError.accessUnavailable
    }
  }

  private func makeBookmark(_ folder: URL) throws -> Data {
    do {
      return try folder.bookmarkData(
        options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
        includingResourceValuesForKeys: nil, relativeTo: nil
      )
    } catch {
      throw FolderAccessError.accessUnavailable
    }
  }

  private func saveBookmark(_ data: Data) throws {
    do {
      try FileManager.default.createDirectory(
        at: bookmarkFile.deletingLastPathComponent(), withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
      )
      try data.write(to: bookmarkFile, options: [.atomic])
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o600], ofItemAtPath: bookmarkFile.path)
    } catch {
      throw FolderAccessError.rememberingFailed
    }
  }

  private func inspect(_ url: URL) -> InventoryItem {
    var info = stat()
    guard lstat(url.path, &info) == 0 else {
      return InventoryItem(
        name: url.lastPathComponent, skipReason: .unavailable,
        byteCount: nil, modificationDate: nil)
    }
    let name = url.lastPathComponent
    let kind = info.st_mode & S_IFMT
    let reason: SkipReason?
    if kind == S_IFLNK || (kind == S_IFREG && info.st_nlink > 1) {
      reason = .link
    } else if info.st_flags & UInt32(SF_DATALESS) != 0 || url.pathExtension.lowercased() == "icloud"
    {
      // Dataless metadata must be checked before any provider-backed resource queries.
      reason = .cloudOnly
    } else if name.hasPrefix(".") || info.st_flags & UInt32(UF_HIDDEN) != 0 {
      reason = .hidden
    } else if ["download", "crdownload", "part", "partial", "filepart", "opdownload"].contains(
      url.pathExtension.lowercased()
    ) {
      reason = .incompleteDownload
    } else {
      do {
        let values = try url.resourceValues(forKeys: [
          .isAliasFileKey, .isPackageKey, .isHiddenKey,
          .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
          .ubiquitousItemIsDownloadingKey,
        ])
        if values.isAliasFile == true {
          reason = .link
        } else if values.ubiquitousItemIsDownloading == true {
          reason = .incompleteDownload
        } else if values.isUbiquitousItem == true
          && values.ubiquitousItemDownloadingStatus != .current
          && values.ubiquitousItemDownloadingStatus != .downloaded
        {
          reason = .cloudOnly
        } else if values.isHidden == true {
          reason = .hidden
        } else if values.isPackage == true {
          reason = .package
        } else if kind == S_IFDIR {
          reason = .folder
        } else if kind != S_IFREG {
          reason = .unsupportedFile
        } else {
          reason = nil
        }
      } catch {
        reason = .unavailable
      }
    }
    var item = InventoryItem(
      name: name, skipReason: reason, byteCount: reason == nil ? info.st_size : nil,
      modificationDate: reason == nil
        ? Date(
          timeIntervalSince1970: Double(info.st_mtimespec.tv_sec)
            + Double(info.st_mtimespec.tv_nsec) / 1_000_000_000) : nil
    )
    item.snapshot = FileSnapshot(info)
    return item
  }
}
