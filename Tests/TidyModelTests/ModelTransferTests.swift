import Darwin
import Foundation
import Network
import Testing
import TidyModel

struct ModelTransferTests {
  @Test(arguments: ["transfer", "loading", "selection"])
  func killedReplacementReopensVerifiedSelectionAndRemovalStaysScoped(checkpoint: String)
    throws
  {
    let server = try HTTPFixture(large: true, honorsRange: true)
    defer { server.stop() }
    let manager = FileManager.default
    let fixture = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? manager.removeItem(at: fixture) }
    let root = fixture.appendingPathComponent("Models")
    try manager.createDirectory(at: root, withIntermediateDirectories: true)
    let unrelated = root.appendingPathComponent("unrelated-data")
    try Data("preserve unrelated storage".utf8).write(to: unrelated)
    let seed = try modelWorker(root: root, mode: "seed", url: server.url)
    try #require(seed.0.terminationReason == .exit && seed.0.terminationStatus == 0)
    let killed = try modelWorker(root: root, mode: checkpoint, url: server.url)
    #expect(killed.0.terminationReason == .uncaughtSignal)
    try #require(killed.0.terminationStatus == SIGKILL)
    #expect(kill(killed.0.processIdentifier, 0) == -1 && errno == ESRCH)
    #expect(
      try Data(contentsOf: root.appendingPathComponent("fixture-v1/config.json"))
        == Data("abc".utf8))
    let expected = checkpoint == "selection" ? "fixture-v2" : "fixture-v1"
    #expect(
      try String(contentsOf: root.appendingPathComponent("active-revision"), encoding: .utf8)
        == expected)
    let requests = server.requestCount
    let restored = try modelWorker(root: root, mode: "restore", url: server.url)
    try #require(restored.0.terminationReason == .exit && restored.0.terminationStatus == 0)
    let state = try JSONDecoder().decode(ModelWorkerSnapshot.self, from: restored.1)
    #expect(state.ready)
    #expect(state.active == expected)
    #expect(server.requestCount == requests)
    #expect(
      state.installed == (checkpoint == "transfer" ? ["fixture-v1"] : ["fixture-v1", "fixture-v2"]))
    #expect(state.partials == (checkpoint == "transfer" ? ["fixture-v2"] : []))
    let removed = try modelWorker(root: root, mode: "remove", url: server.url)
    try #require(removed.0.terminationReason == .exit && removed.0.terminationStatus == 0)
    let empty = try JSONDecoder().decode(ModelWorkerSnapshot.self, from: removed.1)
    #expect(!empty.ready && empty.active == nil)
    #expect(empty.installed.isEmpty && empty.partials.isEmpty)
    #expect(try Data(contentsOf: unrelated) == Data("preserve unrelated storage".utf8))
    let reopened = try modelWorker(root: root, mode: "restore", url: server.url)
    try #require(reopened.0.terminationReason == .exit && reopened.0.terminationStatus == 0)
    let final = try JSONDecoder().decode(ModelWorkerSnapshot.self, from: reopened.1)
    #expect(!final.ready && final.active == nil)
    #expect(final.installed.isEmpty && final.partials.isEmpty)
    #expect(server.requestCount == requests)
    #expect(try Data(contentsOf: unrelated) == Data("preserve unrelated storage".utf8))
  }

  private func modelWorker(root: URL, mode: String, url: URL) throws -> (Process, Data) {
    let arguments = ProcessInfo.processInfo.arguments
    let index = try #require(arguments.firstIndex(of: "--test-bundle-path"))
    let process = Process()
    process.executableURL = URL(fileURLWithPath: arguments[index + 1])
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("TidyModelTestWorker")
    process.arguments = [root.path, mode, url.absoluteString]
    let output = Pipe()
    process.standardOutput = output
    try process.run()
    process.waitUntilExit()
    return (process, output.fileHandleForReading.readDataToEndOfFile())
  }

  @Test(arguments: [false, true])
  func partialCleanupPreservesUnrelatedDataAndRejectsTraversal(archived: Bool) async throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let safe = manager.temporaryDirectory.appendingPathComponent("CFNetworkDownload_\(UUID()).tmp")
    let canary = manager.temporaryDirectory.appendingPathComponent(
      "CFNetworkDownload_\(UUID()).tmp")
    let traversal = manager.temporaryDirectory.appendingPathComponent("CFNetworkDownload_\(UUID())")
    try manager.createDirectory(at: root, withIntermediateDirectories: true)
    defer {
      for path in [root, safe, canary, traversal] { try? manager.removeItem(at: path) }
    }
    try manager.createDirectory(at: traversal, withIntermediateDirectories: false)
    try Data("owned partial".utf8).write(to: safe)
    try Data("unrelated temporary data".utf8).write(to: canary)
    let unrelated = root.appendingPathComponent("unrelated.data")
    try Data("preserve".utf8).write(to: unrelated)
    let names = [
      safe.lastPathComponent, "\(traversal.lastPathComponent)/../\(canary.lastPathComponent)",
    ]
    for (index, name) in names.enumerated() {
      let metadata = ["NSURLSessionResumeInfoTempFileName": name]
      let data =
        archived
        ? try NSKeyedArchiver.archivedData(withRootObject: metadata, requiringSecureCoding: true)
        : try PropertyListSerialization.data(
          fromPropertyList: metadata, format: .binary, options: 0)
      try data.write(to: root.appendingPathComponent("\(index).resume"))
    }
    try Data("corrupt resume record".utf8).write(to: root.appendingPathComponent("invalid.resume"))
    try await URLSessionModelTransfer().discardPartials(in: root)
    #expect(!manager.fileExists(atPath: safe.path))
    #expect(try Data(contentsOf: canary) == Data("unrelated temporary data".utf8))
    #expect(try Data(contentsOf: unrelated) == Data("preserve".utf8))
    #expect(try manager.contentsOfDirectory(atPath: root.path) == ["unrelated.data"])
  }

  @MainActor @Test func setupReportsReceivedBytesBeforeTheCurrentFileCompletes() async throws {
    let server = try HTTPFixture(large: true)
    defer { server.stop() }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let manifest = ModelManifest(
      id: "fixture", revision: "progress-v1", name: "Slow weights fixture",
      files: [
        .init(
          name: "model.safetensors", bytes: 1_000_000,
          sha256: "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0",
          url: server.url)
      ])
    let setup = ModelSetup(
      root: root, manifest: manifest,
      transfer: URLSessionModelTransfer(allowLoopbackHTTP: true), runtime: ProgressFixtureRuntime())
    let operation = Task { await setup.download(consent: true) }
    for _ in 0..<100 {
      if server.sentFirstChunk { break }
      try await Task.sleep(for: .milliseconds(5))
    }
    let sent = server.sentFirstChunk
    try await Task.sleep(for: .milliseconds(100))
    let observed = setup.state
    await operation.value
    #expect(sent, "The server must have sent a partial response before observing progress")
    guard case .downloading(let file, let received, let total) = observed else {
      Issue.record("Expected an in-flight weights download, not a completed or failed transfer")
      return
    }
    #expect(file == "model.safetensors")
    #expect(received > 0, "Received body bytes must be visible before the weights file finishes")
    #expect(received < total)
    #expect(setup.state == .ready)
  }

  @MainActor @Test func corruptAndTruncatedHTTPDownloadsNeverReachReadiness() async throws {
    for truncated in [false, true] {
      let server = try HTTPFixture(badBody: true, truncated: truncated)
      defer { server.stop() }
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: root) }
      let manifest = ModelManifest(
        id: "fixture", revision: "v1", name: "HTTP fixture",
        files: [
          .init(
            name: "config.json", bytes: 3,
            sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
            url: server.url)
        ])
      let setup = ModelSetup(
        root: root, manifest: manifest,
        transfer: URLSessionModelTransfer(allowLoopbackHTTP: true), runtime: NeverLoadRuntime())
      await setup.download(consent: true)
      guard case .failed = setup.state else {
        Issue.record("Bad HTTP body must fail setup")
        continue
      }
      #expect(!FileManager.default.fileExists(atPath: setup.modelDirectory.path))
    }
  }

  @Test func realURLSessionFollowsRedirectAndRecoversFromInvalidResumeData() async throws {
    let server = try HTTPFixture()
    defer { server.stop() }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let target = root.appendingPathComponent("download")
    let resume = root.appendingPathComponent("download.resume")
    try Data("old partial".utf8).write(to: target)
    try Data("invalid resume data".utf8).write(to: resume)
    let file = ModelFile(name: "download", bytes: 3, sha256: "unused", url: server.url)
    try await URLSessionModelTransfer(allowLoopbackHTTP: true).download(
      file, to: target, resumeFile: resume)
    #expect(try Data(contentsOf: target) == Data("abc".utf8))
    #expect(!FileManager.default.fileExists(atPath: resume.path))
  }

  @Test(arguments: [true, false])
  func realInterruptedTransferResumesWithoutAppendingAnIgnoredRange(honorsRange: Bool) async throws
  {
    let server = try HTTPFixture(large: true, honorsRange: honorsRange)
    defer { server.stop() }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let target = root.appendingPathComponent("download")
    let resume = root.appendingPathComponent("download.resume")
    let transfer = URLSessionModelTransfer(allowLoopbackHTTP: true)
    let file = ModelFile(name: "download", bytes: 1_000_000, sha256: "unused", url: server.url)
    let first = Task { try await transfer.download(file, to: target, resumeFile: resume) }
    try await Task.sleep(for: .milliseconds(300))
    first.cancel()
    await #expect(throws: (any Error).self) { try await first.value }
    #expect(!FileManager.default.fileExists(atPath: target.path))
    #expect(FileManager.default.fileExists(atPath: resume.path))
    try await transfer.download(file, to: target, resumeFile: resume)
    #expect(try Data(contentsOf: target) == Data(repeating: 97, count: 1_000_000))
    #expect(!FileManager.default.fileExists(atPath: resume.path))
    #expect(server.sawRange)
  }

  @Test(arguments: ["evict", "discard"])
  func interruptedTransferHandlesRealTemporaryFileLossOrCleanup(action: String) async throws {
    let server = try HTTPFixture(large: true, honorsRange: true)
    defer { server.stop() }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let target = root.appendingPathComponent("download")
    let resume = root.appendingPathComponent("download.resume")
    let file = ModelFile(name: "download", bytes: 1_000_000, sha256: "unused", url: server.url)
    let transfer = URLSessionModelTransfer(allowLoopbackHTTP: true)
    let received = AsyncStream<Int64>.makeStream(bufferingPolicy: .bufferingNewest(1))
    let first = Task {
      defer { received.continuation.finish() }
      try await transfer.download(file, to: target, resumeFile: resume) { bytes in
        if bytes > 0 { received.continuation.yield(bytes) }
      }
    }
    var events = received.stream.makeAsyncIterator()
    let progress = await events.next()
    if progress == nil { try await first.value }
    try #require(progress != nil)
    first.cancel()
    await #expect(throws: (any Error).self) { try await first.value }
    var metadata = try #require(
      PropertyListSerialization.propertyList(from: Data(contentsOf: resume), format: nil)
        as? [String: Any])
    if metadata["$archiver"] != nil {
      let decoder = try NSKeyedUnarchiver(forReadingFrom: Data(contentsOf: resume))
      decoder.requiresSecureCoding = true
      let allowed: [AnyClass] = [
        NSDictionary.self, NSArray.self, NSString.self, NSNumber.self, NSData.self, NSURL.self,
      ]
      metadata = try #require(
        decoder.decodeObject(of: allowed, forKey: "NSKeyedArchiveRootObjectKey") as? [String: Any])
      decoder.finishDecoding()
    }
    let name = try #require(metadata["NSURLSessionResumeInfoTempFileName"] as? String)
    try #require(name == URL(fileURLWithPath: name).lastPathComponent)
    try #require(name.hasPrefix("CFNetworkDownload_"))
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(name)
    defer { try? FileManager.default.removeItem(at: temporary) }
    // Inspect only the partial created by this fixture, never unrelated URLSession temp data.
    let partial = try Data(contentsOf: temporary)
    try #require(!partial.isEmpty && partial.count < 1_000_000)
    try #require(partial == Data(repeating: 97, count: partial.count))
    #expect(!FileManager.default.fileExists(atPath: target.path))
    if action == "evict" {
      try FileManager.default.removeItem(at: temporary)
      try await transfer.download(file, to: target, resumeFile: resume)
      #expect(try Data(contentsOf: target) == Data(repeating: 97, count: 1_000_000))
    } else {
      try await transfer.discardPartials(in: root)
      let temporaryStillExists = FileManager.default.fileExists(atPath: temporary.path)
      #expect(!temporaryStillExists)
      #expect(!FileManager.default.fileExists(atPath: target.path))
    }
    #expect(!FileManager.default.fileExists(atPath: resume.path))
  }
}

private struct ModelWorkerSnapshot: Decodable {
  let ready: Bool
  let active: String?
  let installed: [String]
  let partials: [String]
}

private actor ProgressFixtureRuntime: LocalModelRuntime {
  func loadAndCheck(directory: URL, commit: @Sendable () throws -> Void) async throws {
    try commit()
  }
  func unload() async {}
}

private actor NeverLoadRuntime: LocalModelRuntime {
  func loadAndCheck(directory: URL, commit: @Sendable () throws -> Void) async throws {
    Issue.record("Corrupt downloads must not load")
  }
  func unload() async {}
}

private final class HTTPRecord: @unchecked Sendable {
  private let lock = NSLock()
  private var range = false
  private var firstChunk = false
  private var requests = 0
  var requestCount: Int { lock.withLock { requests } }
  var sawRange: Bool { lock.withLock { range } }
  var sentFirstChunk: Bool { lock.withLock { firstChunk } }
  func recordFirstChunk() { lock.withLock { firstChunk = true } }
  func record(_ request: String) {
    lock.withLock {
      requests += 1
      range = range || request.lowercased().contains("range:")
    }
  }
}

private final class HTTPFixture: @unchecked Sendable {
  let listener: NWListener
  let port: UInt16
  private let record: HTTPRecord
  var sawRange: Bool { record.sawRange }
  var sentFirstChunk: Bool { record.sentFirstChunk }
  var requestCount: Int { record.requestCount }
  var url: URL { URL(string: "http://127.0.0.1:\(port)/redirect")! }
  init(
    large: Bool = false, honorsRange: Bool = false, badBody: Bool = false, truncated: Bool = false
  ) throws {
    let record = HTTPRecord()
    self.record = record
    listener = try NWListener(using: .tcp, on: .any)
    let ready = DispatchSemaphore(value: 0)
    listener.stateUpdateHandler = { state in
      if case .ready = state { ready.signal() }
    }
    listener.newConnectionHandler = { connection in
      connection.start(queue: .global())
      connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { bytes, _, _, _ in
        let request = String(decoding: bytes ?? Data(), as: UTF8.self)
        record.record(request)
        if large {
          let range = request.components(separatedBy: "\r\n").first {
            $0.lowercased().hasPrefix("range:")
          }
          if honorsRange, let range,
            let start = range.split(separator: "=").last?.split(separator: "-").first,
            let offset = Int(start), (0..<1_000_000).contains(offset)
          {
            let headers =
              "HTTP/1.1 206 Partial Content\r\nContent-Length: \(1_000_000 - offset)\r\nContent-Range: bytes \(offset)-999999/1000000\r\nAccept-Ranges: bytes\r\nETag: \"fixture\"\r\nConnection: close\r\n\r\n"
            connection.send(
              content: Data(headers.utf8) + Data(repeating: 97, count: 1_000_000 - offset),
              completion: .contentProcessed { _ in connection.cancel() })
            return
          }
          // Intentionally ignore Range (and change the validator) on the resumed request.
          // URLSession must restart/replace instead of appending to its temporary partial.
          let validator = request.lowercased().contains("range:") ? "changed" : "fixture"
          let headers =
            "HTTP/1.1 200 OK\r\nContent-Length: 1000000\r\nAccept-Ranges: bytes\r\nETag: \"\(validator)\"\r\nLast-Modified: Wed, 21 Oct 2015 07:28:00 GMT\r\nConnection: close\r\n\r\n"
          connection.send(
            content: Data(headers.utf8) + Data(repeating: 97, count: 100_000),
            completion: .contentProcessed { _ in
              record.recordFirstChunk()
              DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                connection.send(
                  content: Data(repeating: 97, count: 900_000),
                  completion: .contentProcessed { _ in connection.cancel() })
              }
            })
          return
        }
        let response =
          request.contains("GET /redirect ")
          ? "HTTP/1.1 302 Found\r\nLocation: /file\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
          : "HTTP/1.1 200 OK\r\nContent-Length: \(truncated ? 4 : 3)\r\nAccept-Ranges: bytes\r\nConnection: close\r\n\r\n\(badBody ? "bad" : "abc")"
        connection.send(
          content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
      }
    }
    listener.start(queue: .global())
    guard ready.wait(timeout: .now() + 5) == .success, let boundPort = listener.port else {
      listener.cancel()
      throw CocoaError(.fileReadUnknown)
    }
    port = boundPort.rawValue
  }
  func stop() { listener.cancel() }
}
