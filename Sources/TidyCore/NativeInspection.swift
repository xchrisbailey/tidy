import Darwin
import Foundation
import TidyInspection

func inspectNativeDocument(_ input: Data, format: String, budget: inout InspectionBudget) throws
  -> InspectionEvidence
{
  let started = ContinuousClock.now
  defer { budget.remainingTime -= started.duration(to: .now) }
  guard budget.remainingTime > .zero else { throw InspectionCode.taskLimit }
  let deadline = started.advanced(by: min(.seconds(3), budget.remainingTime))
  let output: Data
  #if DEBUG
    // SwiftPM's command-line runner has no application/XPC bundle. Only that runner uses the
    // same broker supervisor directly; packaged apps never fall back to an in-process parser.
    let arguments = ProcessInfo.processInfo.arguments
    if URL(fileURLWithPath: arguments[0]).lastPathComponent == "swiftpm-testing-helper",
      let index = arguments.firstIndex(of: "--test-bundle-path"), index + 1 < arguments.count
    {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: arguments[index + 1])
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("TidyInspectionHelper")
      process.arguments = ["--format=\(format)"]
      do {
        output = try WorkerSupervisor.run(input, process: process, deadline: deadline) {
          withUnsafeCurrentTask { $0?.isCancelled == true }
        }
      } catch let failure as WorkerFailure {
        if failure == .cancelled { throw CancellationError() }
        throw InspectionCode(rawValue: failure.rawValue) ?? .unreadable
      }
    } else {
      output = try inspectDocumentService(input, format: format, deadline: deadline)
    }
  #else
    output = try inspectDocumentService(input, format: format, deadline: deadline)
  #endif
  guard output.count <= 100_000,
    let reply = try? JSONDecoder().decode(InspectionReply.self, from: output)
  else { throw InspectionCode.unreadable }
  guard reply.code == "ok" else { throw InspectionCode(rawValue: reply.code) ?? .unreadable }
  guard reply.text.utf8.count <= 16_384,
    (format == "pdf" ? ["wholeDocument", "first3PagesOnly"] : ["wholeImage"]).contains(
      reply.coverage)
  else { throw InspectionCode.inputLimit }
  guard reply.text.filter(\.isLetter).count >= 8,
    !reply.text.unicodeScalars.contains(where: {
      CharacterSet.controlCharacters.contains($0)
        && !CharacterSet.whitespacesAndNewlines.contains($0)
    })
  else { throw InspectionCode.unreadable }
  try Task.checkCancellation()
  guard ContinuousClock.now < deadline else { throw InspectionCode.deadline }
  guard let kind = reply.kind,
    (format == "pdf" ? ["pdfText", "pdfTextAndOCR"] : ["imageOCR"]).contains(kind)
  else { throw InspectionCode.unreadable }
  return InspectionEvidence(kind: kind, text: reply.text, coverage: reply.coverage)
}

// XPC callbacks arrive on Foundation's delivery queue, not on the task blocked in this short poll.
// The condition protects every callback result; no untrusted error descriptions are retained.
private final class ServiceResponse: @unchecked Sendable {
  let condition = NSCondition()
  private var output: Data?
  private var failed = false
  private var acknowledged = false

  func finish(_ value: Data) {
    condition.lock()
    defer { condition.unlock() }
    if value.count <= 100_000 { output = value } else { failed = true }
    condition.broadcast()
  }
  func fail() {
    condition.lock()
    failed = true
    condition.broadcast()
    condition.unlock()
  }
  func acknowledge() {
    condition.lock()
    acknowledged = true
    condition.broadcast()
    condition.unlock()
  }
  func result() throws -> Data? {
    condition.lock()
    defer { condition.unlock() }
    if failed { throw InspectionCode.unavailable }
    return output
  }
  func wait() {
    condition.lock()
    _ = condition.wait(until: Date(timeIntervalSinceNow: 0.005))
    condition.unlock()
  }
  var cleaned: Bool {
    condition.lock()
    defer { condition.unlock() }
    return acknowledged
  }
}

private func inspectDocumentService(
  _ input: Data, format: String, deadline: ContinuousClock.Instant
) throws -> Data {
  guard input.count <= 20 * 1024 * 1024 else { throw InspectionCode.inputLimit }
  let connection = NSXPCConnection(serviceName: inspectionServiceName)
  let response = ServiceResponse()
  connection.remoteObjectInterface = NSXPCInterface(with: InspectionServiceProtocol.self)
  connection.interruptionHandler = { response.fail() }
  connection.invalidationHandler = { response.fail() }
  connection.resume()
  defer { connection.invalidate() }
  guard
    let service = connection.remoteObjectProxyWithErrorHandler({ _ in response.fail() })
      as? InspectionServiceProtocol
  else { throw InspectionCode.unavailable }
  let id = UUID().uuidString
  service.inspectDocument(input, format: format, requestID: id) { response.finish($0) }
  do {
    while true {
      try Task.checkCancellation()
      guard ContinuousClock.now < deadline else { throw InspectionCode.deadline }
      if let result = try response.result() { return result }
      response.wait()
    }
  } catch {
    // Cancellation acknowledgement means the broker has synchronously reaped its child, not just
    // invalidated a connection. If the broker itself dies, the worker's independent fail-stop is
    // the last line of defense; allow it to quiesce before returning. No new worker is started here.
    service.cancel(id) { response.acknowledge() }
    let cleanupDeadline = ContinuousClock.now.advanced(by: .seconds(4))
    while !response.cleaned && ContinuousClock.now < cleanupDeadline { response.wait() }
    throw error
  }
}
