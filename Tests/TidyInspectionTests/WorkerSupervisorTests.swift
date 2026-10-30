import Darwin
import Foundation
import Testing
import TidyInspection

struct WorkerSupervisorTests {
  @Test func cappedInputCanReachWorkerBeforeProcessingDeadline() throws {
    let process = Process()
    process.executableURL = try workerExecutable()
    process.arguments = ["count"]
    let result = try WorkerSupervisor.run(
      Data(repeating: 65, count: 4 * 1024 * 1024), process: process,
      deadline: .now.advanced(by: .seconds(2)), cancelled: { false })
    #expect(result == Data("4194304".utf8))
    #expect(kill(process.processIdentifier, 0) == -1 && errno == ESRCH)
  }

  @Test(arguments: ["hang", "crash", "oversize", "cancel"])
  func failedWorkersAreStoppedAndReaped(kind: String) async throws {
    let process = Process()
    process.executableURL = try workerExecutable()
    process.arguments = [kind == "cancel" ? "hang" : kind]
    let operation = Task {
      try WorkerSupervisor.run(
        Data(), process: process,
        deadline: .now.advanced(by: kind == "hang" ? .milliseconds(200) : .seconds(2))
      ) {
        withUnsafeCurrentTask { $0?.isCancelled == true }
      }
    }
    if kind == "cancel" {
      try await Task.sleep(for: .milliseconds(50))
      operation.cancel()
    }
    let expected: WorkerFailure =
      switch kind {
      case "hang": .deadline
      case "cancel": .cancelled
      case "oversize": .inputLimit
      default: .unreadable
      }
    await #expect(throws: expected) { try await operation.value }
    #expect(process.processIdentifier > 0)
    if kind == "crash" { #expect(process.terminationReason == .uncaughtSignal) }
    #expect(kill(process.processIdentifier, 0) == -1 && errno == ESRCH)
  }

  private func workerExecutable() throws -> URL {
    let arguments = ProcessInfo.processInfo.arguments
    let index = try #require(arguments.firstIndex(of: "--test-bundle-path"))
    return URL(fileURLWithPath: arguments[index + 1])
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("TidyInspectionTestWorker")
  }
}
