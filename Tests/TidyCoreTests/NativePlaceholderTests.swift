import Darwin
import Foundation
import Testing
import TidyCore

struct NativePlaceholderTests {
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
