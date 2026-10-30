import Darwin
import Foundation

public enum WorkerSupervisor {
  // The caller owns the executable/arguments. Neither is derived from inspected document data.
  // This is shared by the XPC broker and direct native tests; the app never spawns a parser itself.
  public static func run(
    _ input: Data, process: Process, deadline: ContinuousClock.Instant,
    errorOutput: FileHandle = .nullDevice,
    cancelled: @Sendable () -> Bool
  ) throws -> Data {
    guard input.count <= 20 * 1024 * 1024 else { throw WorkerFailure.inputLimit }
    // Pipes keep local IPC independent of socket policy in the broker's deny-network profile.
    let incoming = Pipe()
    let outgoing = Pipe()
    let writer = incoming.fileHandleForWriting.fileDescriptor
    let reader = outgoing.fileHandleForReading.fileDescriptor
    defer {
      try? incoming.fileHandleForReading.close()
      try? incoming.fileHandleForWriting.close()
      try? outgoing.fileHandleForReading.close()
      try? outgoing.fileHandleForWriting.close()
    }
    guard fcntl(writer, F_SETNOSIGPIPE, 1) == 0,
      fcntl(writer, F_SETFL, O_NONBLOCK) == 0,
      fcntl(reader, F_SETFL, O_NONBLOCK) == 0,
      fcntl(writer, F_SETFD, FD_CLOEXEC) == 0,
      fcntl(reader, F_SETFD, FD_CLOEXEC) == 0
    else { throw WorkerFailure.unavailable }
    process.environment = ["PATH": "/usr/bin:/bin"]
    process.standardInput = incoming
    process.standardOutput = outgoing
    process.standardError = errorOutput
    process.currentDirectoryURL = process.executableURL?.deletingLastPathComponent()
    func check() throws {
      guard !cancelled() else { throw WorkerFailure.cancelled }
      guard ContinuousClock.now < deadline else { throw WorkerFailure.deadline }
    }
    try check()
    do { try process.run() } catch { throw WorkerFailure.unavailable }
    try? incoming.fileHandleForReading.close()
    try? outgoing.fileHandleForWriting.close()
    defer {
      // Reap synchronously on ALL paths, including malformed/excessive IPC and cancellation.
      // SIGKILL scheduling and waitpid latency are OS-dependent, not a hard wall-clock guarantee.
      if process.isRunning { kill(process.processIdentifier, SIGKILL) }
      process.waitUntilExit()
    }
    var sent = 0
    var output = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    var inputClosed = false
    while true {
      try check()
      var progressed = false
      if sent < input.count {
        let count = input.withUnsafeBytes { bytes in
          write(writer, bytes.baseAddress!.advanced(by: sent), min(4096, input.count - sent))
        }
        if count > 0 {
          progressed = true
          sent += count
        } else if count < 0 && errno == EPIPE {
          inputClosed = true
          sent = input.count
        } else if count < 0 && errno != EAGAIN && errno != EINTR {
          throw WorkerFailure.unreadable
        }
      }
      if sent == input.count && !inputClosed {
        try? incoming.fileHandleForWriting.close()
        inputClosed = true
        progressed = true
      }
      let count = read(reader, &buffer, buffer.count)
      if count > 0 {
        progressed = true
        guard output.count + count <= 100_000 else { throw WorkerFailure.inputLimit }
        output.append(contentsOf: buffer.prefix(count))
      } else if count == 0 {
        break
      } else if errno != EAGAIN && errno != EINTR {
        throw WorkerFailure.unreadable
      }
      // Sleep only under backpressure: a per-chunk sleep throttles a capped multi-MiB input
      // so severely that transport alone exhausts the parser's deadline.
      if !progressed { usleep(5_000) }
    }
    while process.isRunning {
      try check()
      usleep(5_000)
    }
    try check()
    guard process.terminationStatus == 0 else { throw WorkerFailure.unreadable }
    return output
  }
}
