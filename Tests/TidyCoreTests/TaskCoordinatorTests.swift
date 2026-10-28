import Darwin
import Foundation
import Testing
import TidyCore

struct TaskCoordinatorTests {
  @Test func cancellingEmptyInventoryDoesNotRememberANewGrant() async throws {
    let folder = try TemporaryFolder()
    defer { folder.remove() }
    let coordinator = TaskCoordinator(bookmarkFile: folder.bookmarkFile)
    let operation = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await coordinator.selectFolder(folder.url)
    }

    await #expect(throws: CancellationError.self) { try await operation.value }
    #expect(!FileManager.default.fileExists(atPath: folder.bookmarkFile.path))
  }

  @Test func unavailableAndCorruptGrantsNeverFallBackToAnotherFolder() async throws {
    let folder = try TemporaryFolder()
    defer { folder.remove() }
    let coordinator = TaskCoordinator(bookmarkFile: folder.bookmarkFile)
    _ = try await coordinator.selectFolder(folder.url)
    try FileManager.default.removeItem(at: folder.url)
    await #expect(throws: FolderAccessError.self) {
      try await TaskCoordinator(bookmarkFile: folder.bookmarkFile).restoreFolder()
    }
    try Data("invalid bookmark".utf8).write(to: folder.bookmarkFile)
    await #expect(throws: FolderAccessError.savedGrantUnavailable) {
      try await TaskCoordinator(bookmarkFile: folder.bookmarkFile).restoreFolder()
    }
  }

  @Test func rejectsFilesAndLinkedRootsWithoutRememberingThem() async throws {
    let folder = try TemporaryFolder()
    defer { folder.remove() }
    let file = folder.root.appendingPathComponent("file.txt")
    try Data().write(to: file)
    let link = folder.root.appendingPathComponent("linked-folder")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder.url)
    let coordinator = TaskCoordinator(bookmarkFile: folder.bookmarkFile)

    for invalidRoot in [file, link] {
      await #expect(throws: FolderAccessError.notFolder) {
        try await coordinator.selectFolder(invalidRoot)
      }
    }
    #expect(!FileManager.default.fileExists(atPath: folder.bookmarkFile.path))
  }

  @Test func restoresReadOnlySecurityScopedBookmarkAcrossCoordinatorRelaunch() async throws {
    let folder = try TemporaryFolder()
    defer { folder.remove() }
    try Data("keep".utf8).write(to: folder.url.appendingPathComponent("selected.txt"))
    let first = TaskCoordinator(bookmarkFile: folder.bookmarkFile)
    #expect(try await first.restoreFolder() == nil)
    _ = try await first.selectFolder(folder.url)

    let reopened = TaskCoordinator(bookmarkFile: folder.bookmarkFile)
    let restored = try #require(try await reopened.restoreFolder())

    #expect(restored.items.map(\.name) == ["selected.txt"])
    #expect(FileManager.default.fileExists(atPath: folder.bookmarkFile.path))
  }

  @Test func explainsEligibilityAndNeverFollowsLinksOrExistingFolders() async throws {
    let folder = try TemporaryFolder()
    defer { folder.remove() }
    let fm = FileManager.default
    for name in ["ordinary.txt", ".secret", "transfer.crdownload", "transfer.part"] {
      try Data("evidence".utf8).write(to: folder.url.appendingPathComponent(name))
    }
    let flaggedHidden = folder.url.appendingPathComponent("finder-hidden.txt")
    try Data().write(to: flaggedHidden)
    #expect(chflags(flaggedHidden.path, UInt32(UF_HIDDEN)) == 0)
    let alias = folder.url.appendingPathComponent("finder-alias")
    let aliasData = try folder.url.bookmarkData(
      options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil
    )
    try URL.writeBookmarkData(aliasData, to: alias)
    #expect(mkfifo(folder.url.appendingPathComponent("pipe").path, 0o600) == 0)
    for name in ["Existing", "Example.app", "Document.rtfd", "transfer.download"] {
      try fm.createDirectory(
        at: folder.url.appendingPathComponent(name), withIntermediateDirectories: false)
    }
    try fm.createSymbolicLink(
      atPath: folder.url.appendingPathComponent("outside-link").path,
      withDestinationPath: "/etc/passwd")
    try fm.createSymbolicLink(
      atPath: folder.url.appendingPathComponent("broken-link").path,
      withDestinationPath: "/does-not-exist")
    try fm.linkItem(
      at: folder.url.appendingPathComponent("ordinary.txt"),
      to: folder.url.appendingPathComponent("hard-link"))
    try Data("12345".utf8).write(to: folder.url.appendingPathComponent("unknown.binary"))

    let result = try await TaskCoordinator(bookmarkFile: folder.bookmarkFile).selectFolder(
      folder.url)
    let items = Dictionary(uniqueKeysWithValues: result.items.map { ($0.name, $0) })

    #expect(items["unknown.binary"]?.skipReason == nil)
    #expect(items["unknown.binary"]?.byteCount == 5)
    #expect(items["unknown.binary"]?.modificationDate != nil)
    #expect(items[".secret"]?.skipReason == .hidden)
    #expect(items["finder-hidden.txt"]?.skipReason == .hidden)
    #expect(items["finder-alias"]?.skipReason == .link)
    #expect(items["pipe"]?.skipReason == .unsupportedFile)
    #expect(items["Example.app"]?.skipReason == .package)
    #expect(items["Document.rtfd"]?.skipReason == .package)
    #expect(items["Existing"]?.skipReason == .folder)
    #expect(items["outside-link"]?.skipReason == .link)
    #expect(items["broken-link"]?.skipReason == .link)
    #expect(items["ordinary.txt"]?.skipReason == .link)
    #expect(items["hard-link"]?.skipReason == .link)
    for name in ["transfer.crdownload", "transfer.part", "transfer.download"] {
      #expect(items[name]?.skipReason == .incompleteDownload)
    }
  }

  @Test func inventoriesDirectChildrenWithoutReadingOrChangingContents() async throws {
    let folder = try TemporaryFolder()
    defer { folder.remove() }
    let original = Data("private fixture content".utf8)
    let file = folder.url.appendingPathComponent("opaque.unknown")
    try original.write(to: file)
    let nested = folder.url.appendingPathComponent("Existing")
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
    try Data("nested".utf8).write(to: nested.appendingPathComponent("inside.txt"))

    let result = try await TaskCoordinator(bookmarkFile: folder.bookmarkFile).selectFolder(
      folder.url)

    #expect(Set(result.items.map(\.name)) == ["opaque.unknown", "Existing"])
    #expect(try Data(contentsOf: file) == original)
    #expect(try FileManager.default.contentsOfDirectory(atPath: nested.path) == ["inside.txt"])
  }
}

private struct TemporaryFolder {
  let root: URL
  let url: URL
  var bookmarkFile: URL { root.appendingPathComponent("settings/folder.bookmark") }

  init() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent("tidy-test-\(UUID())")
    url = root.appendingPathComponent("Selected")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }

  func remove() {
    try? FileManager.default.removeItem(at: root)
  }
}
