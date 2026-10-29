import CoreGraphics
import CoreText
import Darwin
import Foundation
import TidyCore
import TidyModel
import TidyModelRuntime

extension ModelSmoke {
  static func requireOfflineNetworkDenial() throws {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    if fd < 0 {
      guard errno == EPERM else { throw LocalInferenceError.smokeCheckFailed }
      return
    }
    defer { close(fd) }
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = UInt16(9).bigEndian
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    let result = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    guard result < 0, errno == EPERM else { throw LocalInferenceError.smokeCheckFailed }
  }

  static func controlledPDFSmoke(workerCase: String? = nil) async throws {
    try requireOfflineNetworkDenial()
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "tidy-inspection-\(UUID())")
    let folder = root.appendingPathComponent("Selected")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let original =
      try workerCase.map { Data("%PDF-TIDY \($0)".utf8) }
      ?? syntheticPDF(["Acme Invoice AB123 2026-10-28"])
    let source = folder.appendingPathComponent("scan.pdf")
    try original.write(to: source)
    let bookmark = root.appendingPathComponent("settings/folder.bookmark")
    let coordinator = TaskCoordinator(bookmarkFile: bookmark)
    let data = try folder.bookmarkData(
      options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    var stale = false
    let granted = try URL(
      resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI, .withoutMounting],
      relativeTo: nil, bookmarkDataIsStale: &stale)
    _ = try await coordinator.selectFolderForWriting(granted)
    let request = "Give files readable names based on their contents"
    let operation = Task {
      try await coordinator.planTask(request: request) { _, user, _ in
        if user.contains("untrustedEvidence") {
          return
            #"{"files":[{"sourceID":"f0","title":"Acme Invoice AB123 2026-10-28","name":"Acme Invoice AB123 2026-10-28.pdf","disposition":"apply"}]}"#
        }
        return """
          {"status":"plan","message":"","clauses":[{"text":"\(request)","effect":"rename"}],"sort":{"kind":"none","evidence":"","value":""},"rename":[{"kind":"content","evidence":"\(request)","value":"","from":""}],"selection":{"extensions":[],"nameContains":"","evidence":""},"files":[{"sourceID":"f0","disposition":"apply"}]}
          """
      }
    }
    if workerCase == "disconnect" {
      try await Task.sleep(for: .seconds(1))
      try FileManager.default.removeItem(at: root)
      _exit(0)
    }
    if workerCase == "cancel" {
      try await Task.sleep(for: .milliseconds(250))
      operation.cancel()
      do {
        _ = try await operation.value
        throw LocalInferenceError.smokeCheckFailed
      } catch is CancellationError {
        guard try Data(contentsOf: source) == original else {
          throw LocalInferenceError.smokeCheckFailed
        }
        print("Packaged coordinator cancellation and worker cleanup acknowledgement passed")
        return
      }
    }
    let outcome = try await operation.value
    guard case .plan(let plan) = outcome else { throw LocalInferenceError.smokeCheckFailed }
    if let workerCase, workerCase != "containment" {
      let expected: InspectionCode =
        switch workerCase {
        case "hang": .deadline
        case "oversize": .inputLimit
        default: .unreadable
        }
      guard plan.changes.isEmpty, plan.abstained.first?.inspectionCode == expected,
        try await coordinator.execute(plan).changed.isEmpty,
        try Data(contentsOf: source) == original
      else { throw LocalInferenceError.smokeCheckFailed }
      print("Packaged worker \(workerCase) abstention and cleanup passed")
      return
    }
    guard plan.changes.count == 1 else {
      print(
        "Inspection smoke rejected:", plan.abstained.compactMap(\.inspectionCode).map(\.rawValue))
      throw LocalInferenceError.smokeCheckFailed
    }
    guard try await coordinator.execute(plan).changed.count == 1,
      try Data(contentsOf: folder.appendingPathComponent("Acme Invoice AB123 2026-10-28.pdf"))
        == original
    else { throw LocalInferenceError.smokeCheckFailed }
    try await TaskCoordinator(bookmarkFile: bookmark).undoTask(plan.id)
    guard try Data(contentsOf: source) == original else {
      throw LocalInferenceError.smokeCheckFailed
    }
    print(
      workerCase == "containment"
        ? "Packaged parser profile denied file read, persistent write and network connection; coordinator result and undo passed"
        : "Packaged native PDF coordinator rename, byte preservation and reopened undo passed")
  }

  static func pdfNamingSmoke(_ runtime: MLXLocalModelRuntime) async throws {
    try requireOfflineNetworkDenial()
    for (label, lines, required) in [
      (
        "invoice",
        [
          "Acme Invoice AB123 2026-10-28",
          "This invoice covers professional services provided during October.",
          "Payment is due by bank transfer.",
        ], ["Acme", "Invoice", "AB123", "2026-10-28"]
      ),
      (
        "report",
        [
          "Orion Report ZX789 2026-08-14",
          "This report describes the quarterly results for the research project.",
          "The team completed the planned evaluation and documented its findings.",
        ], ["Orion", "Report", "ZX789", "2026-08-14"]
      ),
      (
        "spanish",
        [
          "Factura Iberia CD456 2026-09-15",
          "Esta factura corresponde a los servicios prestados durante octubre.",
          "El pago se realizará mediante transferencia bancaria.",
        ], ["Factura", "Iberia", "CD456", "2026-09-15"]
      ),
    ] {
      if let example = CommandLine.arguments.first(where: { $0.hasPrefix("--pdf-example=") }),
        example != "--pdf-example=\(label)"
      {
        continue
      }
      try await pdfNamingExample(runtime, label: label, lines: lines, required: required)
    }
  }

  static func pdfNamingExample(
    _ runtime: MLXLocalModelRuntime, label: String, lines: [String], required: [String]
  ) async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("tidy-pdf-\(UUID())")
    let folder = root.appendingPathComponent("Selected")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let original = try syntheticPDF(lines)
    let source = folder.appendingPathComponent("scan.pdf")
    try original.write(to: source)
    let bookmark = root.appendingPathComponent("settings/folder.bookmark")
    let coordinator = TaskCoordinator(bookmarkFile: bookmark)
    let data = try folder.bookmarkData(
      options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    var stale = false
    let granted = try URL(
      resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI, .withoutMounting],
      relativeTo: nil, bookmarkDataIsStale: &stale)
    guard !stale else { throw LocalInferenceError.smokeCheckFailed }
    _ = try await coordinator.selectFolderForWriting(granted)
    let started = ContinuousClock.now
    let outcome = try await coordinator.planTask(
      request: "Give PDFs readable names based on their contents"
    ) {
      system, user, limit in
      try await runtime.completeJSON(system: system, user: user, maximumOutputTokens: limit)
    }
    guard case .plan(let plan) = outcome else { throw LocalInferenceError.smokeCheckFailed }
    let result = try await coordinator.execute(plan)
    guard result.changed.count == 1, let changed = result.changed.first,
      required.allSatisfy({ token in
        changed.destinationName.range(of: token, options: .caseInsensitive) != nil
      }),
      changed.destinationName.hasSuffix(".pdf"),
      try Data(contentsOf: folder.appendingPathComponent(changed.destinationName)) == original
    else { throw LocalInferenceError.smokeCheckFailed }
    try await TaskCoordinator(bookmarkFile: bookmark).undoTask(plan.id)
    guard try Data(contentsOf: source) == original else {
      throw LocalInferenceError.smokeCheckFailed
    }
    print(
      "Offline native PDF \(label) naming passed: preserved bytes/date/ID/extension/language and reopened undo; seconds: \(started.duration(to: .now))"
    )
    await reportMetrics(runtime)
  }

  static func syntheticPDF(_ lines: [String]) throws -> Data {
    let bytes = NSMutableData()
    var box = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let consumer = CGDataConsumer(data: bytes),
      let context = CGContext(consumer: consumer, mediaBox: &box, nil)
    else { throw LocalInferenceError.smokeCheckFailed }
    context.beginPDFPage(nil)
    for (index, text) in lines.enumerated() {
      let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(
          "Helvetica" as CFString, 14, nil)
      ]
      let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: text, attributes: attributes))
      context.textPosition = CGPoint(x: 36, y: 700 - index * 20)
      CTLineDraw(line, context)
    }
    context.endPDFPage()
    context.closePDF()
    return bytes as Data
  }
}
