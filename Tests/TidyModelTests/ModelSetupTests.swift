import Foundation
import Testing
import TidyModel

@MainActor
struct ModelSetupTests {
  @Test func repeatedPassiveRestorationKeepsReadyInferenceRunning() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let runtime = ControlledRuntime()
    let setup = ModelSetup(
      root: root, manifest: fixtureManifest, transfer: ControlledTransfer(), runtime: runtime)
    await setup.download(consent: true)
    let inference = Task { await runtime.generate() }
    await runtime.waitForGeneration()
    async let first: Void = setup.restore()
    async let second: Void = setup.restore()
    _ = await (first, second)
    #expect(setup.state == .ready)
    #expect(setup.activeManifest?.revision == "test-v1")
    #expect(await runtime.loads == 1)
    #expect(await runtime.unloads == 1)
    await runtime.finishGeneration()
    #expect(await inference.value == "Finished requested plan")
    await setup.remove(revision: "test-v1", consent: true)
    #expect(setup.state == .awaitingConsent)
    #expect(await runtime.loadedRevision == nil)
  }

  @Test func replacementPauseResumeAndCancellationKeepOriginalUsableAndCleanPartials() async throws
  {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let next = ModelManifest(
      id: "fixture", revision: "test-v2", name: "Fixture 2", files: fixtureManifest.files)
    let original = ModelSetup(
      root: root, manifest: fixtureManifest, transfer: ControlledTransfer(),
      runtime: ControlledRuntime())
    await original.download(consent: true)
    let transfer = InterruptibleTransfer()
    let runtime = ControlledRuntime()
    let setup = ModelSetup(
      root: root, manifest: fixtureManifest, replacements: [next], transfer: transfer,
      runtime: runtime)
    await setup.restore()
    let operation = Task { await setup.replace(revision: "test-v2", consent: true) }
    await transfer.waitForStart()
    #expect(setup.state == .ready)
    #expect(await runtime.loadedRevision == "test-v1")
    await setup.pause()
    await operation.value
    #expect(setup.state == .ready)
    #expect(setup.activity == .paused)
    let resumed = ModelSetup(
      root: root, manifest: fixtureManifest, replacements: [next], transfer: transfer,
      runtime: runtime)
    await resumed.restore()
    #expect(resumed.activeManifest?.revision == "test-v1")
    await resumed.replace(revision: "test-v2", consent: true)
    #expect(await transfer.usedResume)
    #expect(resumed.activeManifest?.revision == "test-v2")

    let third = ModelManifest(
      id: "fixture", revision: "test-v3", name: "Fixture 3", files: fixtureManifest.files)
    let cancelledTransfer = InterruptibleTransfer()
    let cancelled = ModelSetup(
      root: root, manifest: fixtureManifest, replacements: [next, third],
      transfer: cancelledTransfer, runtime: runtime)
    await cancelled.restore()
    let second = Task { await cancelled.replace(revision: "test-v3", consent: true) }
    await cancelledTransfer.waitForStart()
    await cancelled.cancel()
    await second.value
    #expect(cancelled.state == .ready)
    #expect(cancelled.activity == .cancelled)
    #expect(cancelled.activeManifest?.revision == "test-v2")
    #expect(await runtime.loadedRevision == "test-v2")
    #expect(await cancelledTransfer.writing == false)
    #expect(cancelled.partialBytes == 0)
    #expect(
      !FileManager.default.fileExists(atPath: root.appendingPathComponent("test-v3.partial").path))
  }

  @Test(arguments: ["space", "transfer", "integrity", "activation", "selection"])
  func failedReplacementPreservesWorkingReadinessAndFiles(failure: String) async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let next = ModelManifest(
      id: "fixture", revision: "test-v2", name: "Fixture 2", files: fixtureManifest.files)
    let original = ModelSetup(
      root: root, manifest: fixtureManifest, transfer: ControlledTransfer(),
      runtime: ControlledRuntime())
    await original.download(consent: true)
    let runtime = ControlledRuntime(failedRevision: failure == "activation" ? "test-v2" : nil)
    let transfer = ControlledTransfer(failure: failure)
    let setup = ModelSetup(
      root: root, manifest: fixtureManifest, replacements: [next], transfer: transfer,
      runtime: runtime, availableSpace: { _ in failure == "space" ? 0 : Int64.max })
    await setup.restore()
    if failure == "selection" {
      let selection = root.appendingPathComponent("active-revision")
      try FileManager.default.removeItem(at: selection)
      try FileManager.default.createDirectory(at: selection, withIntermediateDirectories: false)
    }
    await setup.replace(revision: next.revision, consent: true)
    #expect(setup.state == .ready)
    #expect(setup.activeManifest?.revision == "test-v1")
    #expect(await runtime.loadedRevision == "test-v1")
    #expect(await runtime.unloads == 1)
    guard case .failed = setup.activity else {
      Issue.record("Replacement must report its failure separately from readiness")
      return
    }
    #expect(
      try String(contentsOf: root.appendingPathComponent("test-v1/config.json"), encoding: .utf8)
        == "abc")
    if failure == "selection" { return }
    let reopened = ModelSetup(
      root: root, manifest: fixtureManifest, replacements: [next], transfer: transfer,
      runtime: ControlledRuntime())
    await reopened.restore()
    #expect(reopened.activeManifest?.revision == "test-v1")
  }

  @Test func replacementRequiresConsentAndKeepsWorkingModelUntilActivation() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let next = ModelManifest(
      id: "fixture", revision: "test-v2", name: "Fixture 2", files: fixtureManifest.files)
    let runtime = ControlledRuntime()
    let transfer = ControlledTransfer()
    let setup = ModelSetup(
      root: root, manifest: fixtureManifest, replacements: [next], transfer: transfer,
      runtime: runtime)
    await setup.download(consent: true)
    await setup.replace(revision: next.revision, consent: false)
    #expect(setup.activeManifest?.revision == "test-v1")
    #expect(await transfer.requests == 1)
    await setup.replace(revision: next.revision, consent: true)
    #expect(setup.state == .ready)
    #expect(setup.activeManifest?.revision == "test-v2")
    #expect(setup.installedModels.map(\.bytes) == [3, 3])
    #expect(await runtime.unloads == 1)
    let reopened = ModelSetup(
      root: root, manifest: fixtureManifest, replacements: [next], transfer: transfer,
      runtime: runtime)
    await reopened.restore()
    #expect(reopened.activeManifest?.revision == "test-v2")
    await reopened.remove(revision: "test-v1", consent: false)
    #expect(reopened.installedModels.count == 2)
    await reopened.remove(revision: "test-v1", consent: true)
    #expect(reopened.state == .ready)
    await reopened.remove(revision: "test-v2", consent: true)
    #expect(reopened.state == .awaitingConsent)
    #expect(reopened.activeManifest == nil)
    #expect(reopened.installedModels.isEmpty)
  }

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
    #expect(
      try !FileManager.default.contentsOfDirectory(atPath: root.path).contains {
        $0.hasSuffix(".partial")
      })
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
    let relaunched = ModelSetup(
      root: root, manifest: fixtureManifest, transfer: transfer, runtime: runtime)
    await relaunched.restore()
    #expect(relaunched.state != .ready)
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
  let failure: String
  init(failure: String = "") { self.failure = failure }
  func download(_ file: ModelFile, to destination: URL, resumeFile: URL) async throws {
    requests += 1
    if failure == "transfer" { throw URLError(.networkConnectionLost) }
    try Data((failure == "integrity" ? "bad" : "abc").utf8).write(to: destination)
  }
}

private actor ControlledRuntime: LocalModelRuntime {
  private var generation: CheckedContinuation<String, Never>?
  private var generationStarted: CheckedContinuation<Void, Never>?
  func generate() async -> String {
    await withCheckedContinuation {
      generation = $0
      generationStarted?.resume()
      generationStarted = nil
    }
  }
  func waitForGeneration() async {
    if generation != nil { return }
    await withCheckedContinuation { generationStarted = $0 }
  }
  func finishGeneration() {
    generation?.resume(returning: "Finished requested plan")
    generation = nil
  }
  private(set) var loads = 0
  private(set) var unloads = 0
  private(set) var loadedRevision: String?
  let fail: Bool
  let failedRevision: String?
  init(fail: Bool = false, failedRevision: String? = nil) {
    self.fail = fail
    self.failedRevision = failedRevision
  }
  func loadAndCheck(directory: URL, commit: @Sendable () throws -> Void) async throws {
    loads += 1
    if fail || directory.lastPathComponent == failedRevision {
      throw CocoaError(.fileReadCorruptFile)
    }
    try Task.checkCancellation()
    try commit()
    loadedRevision = directory.lastPathComponent
  }
  func unload() async {
    generation?.resume(returning: "Interrupted by unload")
    generation = nil
    unloads += 1
    loadedRevision = nil
  }
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
