import Foundation
import Testing
import TidyModel

@MainActor
struct ModelSetupTests {
  @Test func unavailableMetalDeviceCannotTriggerAnUnusableDownload() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let transfer = ControlledTransfer()
    let setup = ModelSetup(
      root: root, manifest: fixtureManifest,
      hardware: .init(appleSilicon: true, memoryBytes: 36 << 30, metalAvailable: false),
      transfer: transfer, runtime: ControlledRuntime())
    await setup.download(consent: true)
    #expect(setup.state == .unavailable("Metal GPU access is unavailable in this Mac session."))
    #expect(await transfer.requests == 0)
    #expect(!FileManager.default.fileExists(atPath: root.path))
  }

  @Test func lowSpaceAndFailedLoadRemainUnusableWithRecoveryFeedback() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let transfer = ControlledTransfer()
    let runtime = ControlledRuntime(fail: true)
    let lowSpace = ModelSetup(
      root: root, manifest: fixtureManifest, transfer: transfer,
      runtime: runtime, availableSpace: { _ in 0 })
    await lowSpace.download(consent: true)
    guard case .failed(let explanation) = lowSpace.state else {
      Issue.record("Low space must fail")
      return
    }
    #expect(explanation.contains("storage"))
    #expect(await transfer.requests == 0)
    let loadFailure = ModelSetup(
      root: root, manifest: fixtureManifest, transfer: transfer, runtime: runtime)
    await loadFailure.download(consent: true)
    guard case .failed = loadFailure.state else {
      Issue.record("Failed native load must not be ready")
      return
    }
    #expect(await runtime.loads == 1)
  }

  @Test func pauseRelaunchResumeAndCancelWaitForWritersAndCleanOwnedPartials() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let transfer = InterruptibleTransfer()
    let runtime = ControlledRuntime()
    let setup = ModelSetup(
      root: root, manifest: fixtureManifest, transfer: transfer, runtime: runtime)
    let operation = Task { await setup.download(consent: true) }
    await transfer.waitForStart()
    await setup.pause()
    await operation.value
    #expect(setup.state == .paused)
    #expect(await transfer.writing == false)
    let reopened = ModelSetup(
      root: root, manifest: fixtureManifest, transfer: transfer, runtime: runtime)
    await reopened.restore()
    #expect(reopened.state == .paused)
    await reopened.download(consent: true)
    #expect(reopened.state == .ready)
    #expect(await transfer.usedResume)

    try FileManager.default.removeItem(at: reopened.modelDirectory)
    let cancelledTransfer = InterruptibleTransfer()
    let cancelled = ModelSetup(
      root: root, manifest: fixtureManifest, transfer: cancelledTransfer, runtime: runtime)
    let second = Task { await cancelled.download(consent: true) }
    await cancelledTransfer.waitForStart()
    await cancelled.cancel()
    await second.value
    #expect(cancelled.state == .cancelled)
    #expect(await cancelledTransfer.writing == false)
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
  }

  @Test func verifiedFilesStillNeedSuccessfulOfflineLoadBeforeReadiness() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let transfer = ControlledTransfer()
    let runtime = ControlledRuntime()
    let setup = ModelSetup(
      root: root, manifest: fixtureManifest, transfer: transfer, runtime: runtime)
    await setup.download(consent: true)
    #expect(setup.state == .ready)
    #expect(await runtime.loads == 1)
    #expect(await transfer.requests == 1)
    let reopened = ModelSetup(
      root: root, manifest: fixtureManifest, transfer: transfer, runtime: runtime)
    #expect(reopened.state != .ready)
    await reopened.restore()
    #expect(reopened.state == .ready)
    #expect(await transfer.requests == 1)
    #expect(await runtime.loads == 2)
    try Data("bad".utf8).write(to: setup.modelDirectory.appendingPathComponent("config.json"))
    await reopened.restore()
    #expect(reopened.state != .ready)
    #expect(await runtime.loads == 2)
  }

  @Test func consentAndUnsupportedHardwareNeverStartATransfer() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let transfer = ControlledTransfer()
    let setup = ModelSetup(
      root: root, manifest: fixtureManifest,
      hardware: .init(appleSilicon: true, memoryBytes: 36 << 30),
      transfer: transfer, runtime: ControlledRuntime())
    await setup.download(consent: false)
    #expect(setup.state == .awaitingConsent)
    #expect(await transfer.requests == 0)
    #expect(!FileManager.default.fileExists(atPath: root.path))

    let unsupported = ModelSetup(
      root: root, manifest: fixtureManifest,
      hardware: .init(appleSilicon: false, memoryBytes: 36 << 30),
      transfer: transfer, runtime: ControlledRuntime())
    await unsupported.download(consent: true)
    #expect(unsupported.state == .unavailable("The local model requires an Apple silicon Mac."))
    #expect(await transfer.requests == 0)
  }
}

private let fixtureManifest = ModelManifest(
  id: "fixture", revision: "test-v1", name: "Fixture",
  files: [
    .init(
      name: "config.json", bytes: 3,
      sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
      url: URL(string: "https://example.invalid/config.json")!)
  ])

private actor ControlledTransfer: ModelTransfer {
  private(set) var requests = 0
  func download(_ file: ModelFile, to destination: URL, resumeFile: URL) async throws {
    requests += 1
    try Data("abc".utf8).write(to: destination)
  }
}

private actor ControlledRuntime: LocalModelRuntime {
  private(set) var loads = 0
  let fail: Bool
  init(fail: Bool = false) { self.fail = fail }
  func loadAndCheck(directory: URL) async throws {
    loads += 1
    if fail { throw CocoaError(.fileReadCorruptFile) }
  }
  func unload() async {}
}

private actor InterruptibleTransfer: ModelTransfer {
  private(set) var writing = false
  private(set) var usedResume = false
  private var started: CheckedContinuation<Void, Never>?
  func waitForStart() async {
    if writing { return }
    await withCheckedContinuation { started = $0 }
  }
  func download(_ file: ModelFile, to destination: URL, resumeFile: URL) async throws {
    if FileManager.default.fileExists(atPath: resumeFile.path) {
      usedResume = true
      try Data("abc".utf8).write(to: destination)
      return
    }
    writing = true
    started?.resume()
    started = nil
    do {
      try await Task.sleep(for: .seconds(60))
    } catch {
      // Emulate URLSession delivering resume data only after its writer has stopped.
      try Data("opaque resume".utf8).write(to: resumeFile)
      writing = false
      throw error
    }
  }
}
