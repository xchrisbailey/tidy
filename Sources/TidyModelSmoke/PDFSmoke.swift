import CoreGraphics
import CoreText
import Foundation
import TidyCore
import TidyModel
import TidyModelRuntime

extension ModelSmoke {
  static func pdfNamingSmoke(_ runtime: MLXLocalModelRuntime) async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("tidy-pdf-\(UUID())")
    let folder = root.appendingPathComponent("Selected")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let bytes = NSMutableData()
    var box = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let consumer = CGDataConsumer(data: bytes),
      let context = CGContext(consumer: consumer, mediaBox: &box, nil)
    else { throw LocalInferenceError.smokeCheckFailed }
    context.beginPDFPage(nil)
    for (index, text) in [
      "Acme Invoice AB123 2026-10-28",
      "This invoice covers professional services provided during October.",
      "Payment is due by bank transfer.",
    ].enumerated() {
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
    let original = bytes as Data
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
      request: "Give files readable names based on their contents"
    ) {
      system, user, limit in
      return try await runtime.completeJSON(system: system, user: user, maximumOutputTokens: limit)
    }
    guard case .plan(let plan) = outcome else { throw LocalInferenceError.smokeCheckFailed }
    let result = try await coordinator.execute(plan)
    guard result.changed.count == 1, let changed = result.changed.first,
      ["Acme", "Invoice", "AB123", "2026-10-28"].allSatisfy(changed.destinationName.contains),
      changed.destinationName.hasSuffix(".pdf"),
      try Data(contentsOf: folder.appendingPathComponent(changed.destinationName)) == original
    else { throw LocalInferenceError.smokeCheckFailed }
    try await TaskCoordinator(bookmarkFile: bookmark).undoTask(plan.id)
    guard try Data(contentsOf: source) == original else {
      throw LocalInferenceError.smokeCheckFailed
    }
    print(
      "Offline native PDF evidence naming passed: preserved bytes/date/ID/extension and reopened undo; seconds: \(started.duration(to: .now))"
    )
    await reportMetrics(runtime)
  }
}
