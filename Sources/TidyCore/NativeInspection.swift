import Darwin
import Foundation

// One child per inspection, serially awaited by the existing content stage. Only authorized capped
// bytes cross this socket; the helper never receives source paths or filesystem operation authority.
func inspectNativePDF(_ input: Data, budget: inout InspectionBudget) throws -> InspectionEvidence {
  let started = ContinuousClock.now
  defer { budget.remainingTime -= started.duration(to: .now) }
  guard budget.remainingTime > .zero else { throw InspectionCode.taskLimit }
  let deadline = started.advanced(by: min(.seconds(3), budget.remainingTime))
  let process = Process()
  var executable = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
    .deletingLastPathComponent().appendingPathComponent("TidyInspectionHelper")
  #if DEBUG
    let arguments = ProcessInfo.processInfo.arguments
    if URL(fileURLWithPath: arguments[0]).lastPathComponent == "swiftpm-testing-helper",
      let index = arguments.firstIndex(of: "--test-bundle-path"), index + 1 < arguments.count
    {
      executable = URL(fileURLWithPath: arguments[index + 1])
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("TidyInspectionHelper")
    }
  #endif
  guard FileManager.default.isExecutableFile(atPath: executable.path) else {
    throw InspectionCode.unavailable
  }
  var sockets: [Int32] = [-1, -1]
  guard socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets) == 0 else {
    throw InspectionCode.unavailable
  }
  let parent = sockets[0]
  let child = FileHandle(fileDescriptor: sockets[1], closeOnDealloc: true)
  defer {
    close(parent)
    try? child.close()
  }
  var enabled: Int32 = 1
  guard
    setsockopt(parent, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
      == 0,
    fcntl(parent, F_SETFL, O_NONBLOCK) == 0,
    fcntl(parent, F_SETFD, FD_CLOEXEC) == 0,
    fcntl(sockets[1], F_SETFD, FD_CLOEXEC) == 0
  else { throw InspectionCode.unavailable }
  process.executableURL = executable
  process.environment = ["PATH": "/usr/bin:/bin"]
  process.standardInput = child
  process.standardOutput = child
  process.standardError = FileHandle.nullDevice
  do { try process.run() } catch { throw InspectionCode.unavailable }
  try? child.close()
  defer {
    // SIGKILL rather than an unbounded graceful wait: reap before returning, including cancellation,
    // invalid IPC and timeouts. OS scheduling/reaping latency is not a hard wall-clock guarantee.
    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    process.waitUntilExit()
  }
  var sent = 0
  var output = Data()
  var buffer = [UInt8](repeating: 0, count: 4096)
  var inputClosed = false
  while true {
    try Task.checkCancellation()
    guard ContinuousClock.now < deadline else { throw InspectionCode.deadline }
    if sent < input.count {
      let count = input.withUnsafeBytes { bytes in
        send(parent, bytes.baseAddress!.advanced(by: sent), min(4096, input.count - sent), 0)
      }
      if count > 0 {
        sent += count
      } else if count < 0 && errno == EPIPE {
        // A fail-closed helper may reply before consuming all input (for example, containment
        // initialization failed). Drain its bounded reply instead of losing the safe reason code.
        inputClosed = true
        sent = input.count
      } else if count < 0 && errno != EAGAIN && errno != EINTR {
        throw InspectionCode.unreadable
      }
    }
    if sent == input.count && !inputClosed {
      shutdown(parent, SHUT_WR)
      inputClosed = true
    }
    let count = recv(parent, &buffer, buffer.count, 0)
    if count > 0 {
      guard output.count + count <= 100_000 else { throw InspectionCode.inputLimit }
      output.append(contentsOf: buffer.prefix(count))
    } else if count == 0 {
      break
    } else if errno != EAGAIN && errno != EINTR {
      throw InspectionCode.unreadable
    }
    usleep(5_000)
  }
  while process.isRunning {
    try Task.checkCancellation()
    guard ContinuousClock.now < deadline else { throw InspectionCode.deadline }
    usleep(5_000)
  }
  struct Reply: Decodable {
    let code: String
    let text: String
    let coverage: String
  }
  guard process.terminationStatus == 0,
    let reply = try? JSONDecoder().decode(Reply.self, from: output)
  else { throw InspectionCode.unreadable }
  guard reply.code == "ok" else { throw InspectionCode(rawValue: reply.code) ?? .unreadable }
  guard reply.text.utf8.count <= 16_384,
    ["wholeDocument", "first3PagesOnly"].contains(reply.coverage)
  else { throw InspectionCode.inputLimit }
  try Task.checkCancellation()
  guard ContinuousClock.now < deadline else { throw InspectionCode.deadline }
  return InspectionEvidence(kind: "pdfText", text: reply.text, coverage: reply.coverage)
}
