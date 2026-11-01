import Darwin
import Foundation
import Testing
import TidyCore

struct NativePlaceholderTests {
  @Test(.enabled(if: ProcessInfo.processInfo.environment["TIDY_PROVIDER_FIXTURE_ROOT"] != nil))
  func realProviderRefreshRecursivePlanAndFreshProcessPreservePlaceholders() throws {
    let path = try #require(ProcessInfo.processInfo.environment["TIDY_PROVIDER_FIXTURE_ROOT"])
    let folder = URL(fileURLWithPath: path, isDirectory: true)
    let placeholders = ["cloud-only.txt", "Nested/nested-cloud-only.txt"]
    let downloaded = ["downloaded.txt", "Nested/nested-downloaded.txt"]
    let settings = FileManager.default.temporaryDirectory.appendingPathComponent(
      "tidy-provider-\(UUID())")
    defer { try? FileManager.default.removeItem(at: settings) }
    for name in placeholders + downloaded {
      let values = try folder.appendingPathComponent(name).resourceValues(forKeys: [
        .isUbiquitousItemKey
      ])
      try #require(values.isUbiquitousItem == true)
    }
    for name in placeholders {
      let state = try placeholderState(folder.appendingPathComponent(name))
      try #require(state.dataless && state.notDownloaded && !state.downloading)
    }
    // Only confirmed downloaded fixture contents are read; never hash/open placeholders.
    let contents = try downloaded.map { name in
      let url = folder.appendingPathComponent(name)
      let state = try placeholderState(url)
      try #require(!state.dataless && !state.notDownloaded && !state.downloading)
      return try Data(contentsOf: url)
    }
    let executable = try workerExecutable()
    for mode in ["select", "restore", "restore"] {
      let worker = Process()
      worker.executableURL = executable
      worker.arguments = [folder.path, settings.path, mode]
      try worker.run()
      worker.waitUntilExit()
      try #require(worker.terminationReason == .exit && worker.terminationStatus == 0)
      for name in placeholders {
        let state = try placeholderState(folder.appendingPathComponent(name))
        #expect(state.dataless && state.notDownloaded && !state.downloading)
      }
      for (name, original) in zip(downloaded, contents) {
        let url = folder.appendingPathComponent(name)
        let state = try placeholderState(url)
        #expect(!state.dataless && !state.notDownloaded && !state.downloading)
        #expect(try Data(contentsOf: url) == original)
      }
    }
  }

  private func workerExecutable() throws -> URL {
    if let path = ProcessInfo.processInfo.environment["TIDY_PROVIDER_TEST_WORKER"] {
      return URL(fileURLWithPath: path)
    }
    let arguments = ProcessInfo.processInfo.arguments
    let index = try #require(arguments.firstIndex(of: "--test-bundle-path"))
    return URL(fileURLWithPath: arguments[index + 1])
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("TidyProviderTestWorker")
  }

  // Real provider fixtures are opt-in; an ordinary file cannot stand in for a placeholder.
  @Test(
    .enabled(
      if: ProcessInfo.processInfo.environment["TIDY_PLACEHOLDER_PATH"] != nil
        && ProcessInfo.processInfo.environment["TIDY_DOWNLOADED_PATH"] != nil))
  func realProviderPlaceholderRemainsUnhydratedAndDownloadedFileIsEligible() async throws {
    let environment = ProcessInfo.processInfo.environment
    let placeholder = URL(fileURLWithPath: try #require(environment["TIDY_PLACEHOLDER_PATH"]))
    let downloaded = URL(fileURLWithPath: try #require(environment["TIDY_DOWNLOADED_PATH"]))
    let folder = placeholder.deletingLastPathComponent()
    #expect(
      folder.standardizedFileURL == downloaded.deletingLastPathComponent().standardizedFileURL)
    let before = try placeholderState(placeholder)
    #expect(before.dataless || before.notDownloaded)
    #expect(!before.downloading)

    let settings = FileManager.default.temporaryDirectory.appendingPathComponent(
      "tidy-native-\(UUID())")
    defer { try? FileManager.default.removeItem(at: settings) }
    let coordinator = TaskCoordinator(
      bookmarkFile: settings.appendingPathComponent("folder.bookmark"))
    let inventory = try await coordinator.selectFolder(folder)
    #expect(
      inventory.items.first { $0.name == placeholder.lastPathComponent }?.skipReason == .cloudOnly)
    let downloadedItem = try #require(
      inventory.items.first { $0.name == downloaded.lastPathComponent })
    #expect(downloadedItem.skipReason == nil)

    try await Task.sleep(for: .seconds(2))
    let after = try placeholderState(placeholder)
    #expect(after.dataless == before.dataless)
    #expect(after.notDownloaded == before.notDownloaded)
    #expect(!after.downloading)
  }

  private func placeholderState(_ url: URL) throws -> (
    dataless: Bool, notDownloaded: Bool, downloading: Bool
  ) {
    var info = stat()
    try #require(lstat(url.path, &info) == 0)
    let values = try url.resourceValues(forKeys: [
      .ubiquitousItemDownloadingStatusKey, .ubiquitousItemIsDownloadingKey,
    ])
    return (
      info.st_flags & UInt32(SF_DATALESS) != 0,
      values.ubiquitousItemDownloadingStatus == .notDownloaded,
      values.ubiquitousItemIsDownloading == true
    )
  }
}
