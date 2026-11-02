import Darwin
import Foundation
import Testing

struct FilesystemIdentityQualificationTests {
  @Test(.enabled(if: ProcessInfo.processInfo.environment["TIDY_IDENTITY_TEST_WORKER"] != nil))
  func descriptorCaptureRejectsLinksAndSpecialFiles() throws {
    let worker = URL(
      fileURLWithPath: try #require(
        ProcessInfo.processInfo.environment["TIDY_IDENTITY_TEST_WORKER"])
    )
    .resolvingSymlinksInPath()
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
      "tidy-identity-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: folder) }
    let original = folder.appendingPathComponent("file.txt")
    try Data("synthetic fixture".utf8).write(to: original)
    let link = folder.appendingPathComponent("link")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
    let fifo = folder.appendingPathComponent("fifo")
    try #require(mkfifo(fifo.path, 0o600) == 0)
    for target in [link, fifo] {
      let (process, data) = try run(worker, target)
      #expect(process.terminationReason == .exit && process.terminationStatus == 2)
      #expect(data.isEmpty)
    }
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["TIDY_IDENTITY_TEST_WORKER"] != nil))
  func descriptorIdentitySurvivesDirectoryBirthTimeRewrite() throws {
    let worker = URL(
      fileURLWithPath: try #require(
        ProcessInfo.processInfo.environment["TIDY_IDENTITY_TEST_WORKER"])
    )
    .resolvingSymlinksInPath()
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
      "tidy-identity-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: folder) }
    let before = try capture(worker, folder)
    var birth = timespec(tv_sec: Int(before.birthSeconds), tv_nsec: Int(before.birthNanoseconds))
    birth.tv_nsec += birth.tv_nsec < 999_999_926 ? 74 : -74
    var attributes = attrlist()
    attributes.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
    attributes.commonattr = attrgroup_t(ATTR_CMN_CRTIME)
    try #require(
      setattrlist(
        folder.path, &attributes, &birth, MemoryLayout<timespec>.size, UInt32(FSOPT_NOFOLLOW)) == 0)
    let after = try capture(worker, folder)
    #expect(after.fileID == before.fileID && after.volumeUUID == before.volumeUUID)
    #expect(after.birthSeconds == before.birthSeconds)
    #expect(after.birthNanoseconds == birth.tv_nsec)
    #expect(after.birthNanoseconds != before.birthNanoseconds)
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["TIDY_IDENTITY_TEST_WORKER"] != nil))
  func descriptorIdentitySurvivesRenameAndDistinguishesReplacement() throws {
    let worker = URL(
      fileURLWithPath: try #require(
        ProcessInfo.processInfo.environment["TIDY_IDENTITY_TEST_WORKER"])
    )
    .resolvingSymlinksInPath()
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
      "tidy-identity-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: folder) }
    let original = folder.appendingPathComponent("original.txt")
    let renamed = folder.appendingPathComponent("renamed.txt")
    try Data("synthetic identity fixture".utf8).write(to: original)
    let first = try capture(worker, original)
    try #require(first.fileID != 0 && first.volumeUUID != nil)
    try FileManager.default.moveItem(at: original, to: renamed)
    let moved = try capture(worker, renamed)
    #expect(moved.fileID == first.fileID && moved.volumeUUID == first.volumeUUID)
    try Data("synthetic identity fixture".utf8).write(to: original)
    let replacement = try capture(worker, original)
    #expect(replacement.fileID != first.fileID)
    #expect(replacement.volumeUUID == first.volumeUUID)
    let cloned = folder.appendingPathComponent("clone.txt")
    try FileManager.default.copyItem(at: renamed, to: cloned)
    let copied = try capture(worker, cloned)
    #expect(copied.fileID != first.fileID && copied.fileID != replacement.fileID)
    #expect(copied.volumeUUID == first.volumeUUID)
  }

  private func capture(_ worker: URL, _ target: URL) throws -> Capture {
    let (process, data) = try run(worker, target)
    try #require(process.terminationReason == .exit && process.terminationStatus == 0)
    let capture = try JSONDecoder().decode(Capture.self, from: data)
    try #require(capture.pathFromIDValid && capture.pathFromIDSupported)
    try #require(capture.documentedCapabilityCandidate)
    return capture
  }

  private func run(_ worker: URL, _ target: URL) throws -> (Process, Data) {
    let resolved = try #require(realpath(target.deletingLastPathComponent().path, nil))
    defer { free(resolved) }
    let parent = String(cString: resolved)
    let targetPath = parent + "/" + target.lastPathComponent
    var info = stat()
    try #require(lstat(targetPath, &info) == 0)
    let scope = info.st_mode & S_IFMT == S_IFDIR ? targetPath : parent
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
    let literals = [worker.path, scope]
    let escaped = literals.map {
      $0.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
    // Deny home/session-temp reads except the fixture and executable; system paths
    // remain available for dyld. This is not a general untrusted-code sandbox.
    let policy = """
      (version 1) (allow default) (deny network*) (deny file-write*) (deny process-fork)
      (deny file-read* (subpath "/Users") (subpath "/private/var/folders"))
      (allow file-read* (literal "\(escaped[0])") (subpath "\(escaped[1])"))
      """
    process.arguments = ["-p", policy, worker.path, "capture", targetPath]
    process.environment = [
      "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": parent,
      "TMPDIR": parent + "/", "LC_ALL": "C",
    ]
    let output = Pipe()
    process.standardOutput = output
    try process.run()
    let timer = DispatchSource.makeTimerSource(queue: .global())
    timer.schedule(deadline: .now() + .seconds(15))
    timer.setEventHandler {
      if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }
    timer.resume()
    defer {
      timer.cancel()
      if process.isRunning {
        process.terminate()
        process.waitUntilExit()
      }
      try? output.fileHandleForReading.close()
    }
    var data = Data()
    while let chunk = try output.fileHandleForReading.read(upToCount: 4097 - data.count),
      !chunk.isEmpty
    {
      data.append(chunk)
      try #require(data.count <= 4096)
    }
    process.waitUntilExit()
    return (process, data)
  }
}

private struct Capture: Decodable {
  let fileID: UInt64
  let volumeUUID: String?
  let birthSeconds: Int64
  let birthNanoseconds: Int64
  let pathFromIDSupported: Bool
  let pathFromIDValid: Bool
  let documentedCapabilityCandidate: Bool
}
