import Foundation
import Network
import Testing
import TidyModel

struct ModelTransferTests {
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
  var sawRange: Bool { lock.withLock { range } }
  func record(_ request: String) {
    lock.withLock { range = range || request.lowercased().contains("range:") }
  }
}

private final class HTTPFixture: @unchecked Sendable {
  let listener: NWListener
  let port: UInt16
  private let record: HTTPRecord
  var sawRange: Bool { record.sawRange }
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
