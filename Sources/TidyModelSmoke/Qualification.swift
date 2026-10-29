import Foundation
import TidyCore
import TidyModelRuntime

struct QualificationFixture: Decodable {
  let id: String
  let format: String
  let name: String
  let lines: [String]
  let required: [String]
  let eligible: Bool

  func bytes() throws -> Data {
    switch format {
    case "pdf": try ModelSmoke.syntheticPDF(lines)
    case "png": try ModelSmoke.syntheticOCR(lines, scanned: false)
    case "scan": try ModelSmoke.syntheticOCR(lines, scanned: true)
    case "invalid": Data("not a PDF".utf8)
    default: Data(lines.joined(separator: "\n").utf8)
    }
  }
}

extension ModelSmoke {
  static func qualificationErrorCode(_ error: Error) -> String {
    switch error {
    case LocalInferenceError.contextLimit: "contextLimit"
    case LocalInferenceError.outputLimit: "outputLimit"
    case PlanningError.invalidResponse: "invalidResponse"
    case PlanningError.requestTooLarge: "requestTooLarge"
    case is CancellationError: "cancelled"
    default: "other"
    }
  }

  static func qualificationPerformance(
    _ runtime: MLXLocalModelRuntime, loadingTime: Duration
  ) async throws {
    try requireOfflineNetworkDenial()
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "tidy-qualification-performance-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let passed = try await qualificationBatch(
      runtime, root: root, fixtures: [], loadingTime: loadingTime)
    guard passed else { throw LocalInferenceError.smokeCheckFailed }
  }

  static func qualificationCoordinator(_ folder: URL, bookmark: URL) async throws -> TaskCoordinator
  {
    let data = try folder.bookmarkData(
      options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    var stale = false
    let granted = try URL(
      resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI, .withoutMounting],
      relativeTo: nil, bookmarkDataIsStale: &stale)
    guard !stale else { throw LocalInferenceError.smokeCheckFailed }
    let coordinator = TaskCoordinator(bookmarkFile: bookmark)
    _ = try await coordinator.selectFolderForWriting(granted)
    return coordinator
  }

  static func qualification(_ runtime: MLXLocalModelRuntime, loadingTime: Duration) async throws {
    try requireOfflineNetworkDenial()
    guard
      let corpusURL = Bundle.module.url(forResource: "QualificationCorpus", withExtension: "json")
    else { throw LocalInferenceError.smokeCheckFailed }
    let fixtures = try JSONDecoder().decode(
      [QualificationFixture].self, from: Data(contentsOf: corpusURL))
    guard fixtures.count == 32, fixtures.filter(\.eligible).count == 24 else {
      throw LocalInferenceError.smokeCheckFailed
    }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "tidy-qualification-v1-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let heartbeat = Task { @MainActor in
      var last = ContinuousClock.now
      var maximum = Duration.zero
      var ticks = 0
      while !Task.isCancelled {
        do { try await Task.sleep(for: .milliseconds(100)) } catch { break }
        let now = ContinuousClock.now
        maximum = max(maximum, last.duration(to: now))
        last = now
        ticks += 1
      }
      print("QUAL heartbeat ticks=\(ticks) maximumMainActorGap=\(maximum); not native UI evidence")
    }
    defer { heartbeat.cancel() }
    let metadataPassed = try await qualificationBatch(
      runtime, root: root, fixtures: [], loadingTime: loadingTime)
    var proposed = 0
    var usable = 0
    var useful = 0
    var abstained = 0
    var unchanged = 0
    var skipped = 0
    var errors = 0
    for fixture in fixtures {
      let work = root.appendingPathComponent(fixture.id)
      let folder = work.appendingPathComponent("Selected")
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let original = try fixture.bytes()
      let source = folder.appendingPathComponent(fixture.name)
      try original.write(to: source)
      let bookmark = work.appendingPathComponent("settings/folder.bookmark")
      let coordinator = try await qualificationCoordinator(folder, bookmark: bookmark)
      let start = ContinuousClock.now
      do {
        let outcome = try await coordinator.planTask(
          request: "Give files readable names based on their contents"
        ) { system, user, limit in
          try await runtime.completeJSON(system: system, user: user, maximumOutputTokens: limit)
        }
        guard case .plan(let plan) = outcome else {
          errors += 1
          print("QUAL \(fixture.id) noPlan eligible=\(fixture.eligible)")
          continue
        }
        abstained += plan.abstained.count
        unchanged += plan.unchanged.count
        skipped += plan.skipped.count
        for change in plan.changes {
          proposed += 1
          let protected = fixture.required.filter { $0.contains(where: \.isNumber) }
          let acceptable =
            !fixture.required.isEmpty
            && fixture.required.allSatisfy {
              change.destinationName.range(of: $0, options: .caseInsensitive) != nil
            }
            && protected.allSatisfy { change.destinationName.contains($0) }
            && URL(fileURLWithPath: change.destinationName).pathExtension
              == URL(fileURLWithPath: fixture.name).pathExtension
            && change.destinationName.count <= 140
          usable += acceptable ? 1 : 0
          useful += acceptable && fixture.eligible ? 1 : 0
          // Only generated synthetic public operation paths are recorded, never completions/evidence.
          let encoded = try JSONEncoder().encode(change.destinationName)
          print(
            "QUAL \(fixture.id) proposal=\(String(decoding: encoded, as: UTF8.self)) descriptorPass=\(acceptable) eligible=\(fixture.eligible)"
          )
        }
        let result = try await coordinator.execute(plan)
        guard result.failed.isEmpty, result.skipped.count == plan.skipped.count,
          result.changed.count == plan.changes.count
        else { throw LocalInferenceError.smokeCheckFailed }
        for change in result.changed {
          guard
            try Data(contentsOf: folder.appendingPathComponent(change.destinationName)) == original
          else { throw LocalInferenceError.smokeCheckFailed }
        }
        if !result.changed.isEmpty {
          try await TaskCoordinator(bookmarkFile: bookmark).undoTask(plan.id)
        }
        guard try Data(contentsOf: source) == original else {
          throw LocalInferenceError.smokeCheckFailed
        }
        print(
          "QUAL \(fixture.id) changes=\(plan.changes.count) abstained=\(plan.abstained.count) unchanged=\(plan.unchanged.count) skipped=\(plan.skipped.count) codes=\(plan.abstained.compactMap(\.inspectionCode).map(\.rawValue)) byteAndUndo=pass seconds=\(start.duration(to: .now))"
        )
      } catch {
        errors += 1
        print(
          "QUAL \(fixture.id) errorCode=\(qualificationErrorCode(error)) seconds=\(start.duration(to: .now))"
        )
        // Do not log arbitrary runtime errors or replace a failed cohort member with another fixture.
      }
      reportMemory("QUAL \(fixture.id)")
    }
    print(
      "QUAL SUMMARY proposed=\(proposed) descriptorUsable=\(usable) crypticUseful=\(useful)/24 abstained=\(abstained) unchanged=\(unchanged) skipped=\(skipped) errors=\(errors); agent semantic review required"
    )
    let contentHeavySucceeded = try await qualificationBatch(
      runtime, root: root, fixtures: Array(fixtures.filter(\.eligible).prefix(12)),
      loadingTime: .zero)
    let operation = Task {
      try await runtime.completeJSON(
        system: "Return only a JSON array of integers.",
        user: "List all integers from 1 to 1000 in order.", maximumOutputTokens: 2048)
    }
    try await Task.sleep(for: .milliseconds(100))
    let cancellationStart = ContinuousClock.now
    operation.cancel()
    var cancellationSucceeded = false
    do {
      _ = try await operation.value
      print("QUAL cancellation FAILED: generation completed before cancellation")
    } catch is CancellationError {
      cancellationSucceeded = true
      print("QUAL nativeCancellationDrained=\(cancellationStart.duration(to: .now))")
    }
    reportMemory("QUAL final")
    heartbeat.cancel()
    await heartbeat.value
    let descriptorGate = proposed > 0 && Double(usable) / Double(proposed) >= 0.9
    let crypticGate = Double(useful) / 24 >= 0.8
    print(
      "QUAL gates metadata100=\(metadataPassed) contentHeavyCompleted=\(contentHeavySucceeded) cancellation=\(cancellationSucceeded) noErrors=\(errors == 0) descriptorUpperBound90=\(descriptorGate) crypticUpperBound80=\(crypticGate); semantic/human gates remain separate"
    )
    guard metadataPassed, contentHeavySucceeded, cancellationSucceeded, errors == 0,
      descriptorGate, crypticGate
    else {
      throw LocalInferenceError.smokeCheckFailed
    }
  }

  static func qualificationBatch(
    _ runtime: MLXLocalModelRuntime, root: URL, fixtures: [QualificationFixture],
    loadingTime: Duration
  ) async throws -> Bool {
    let metadata = fixtures.isEmpty
    let label = metadata ? "metadata100" : "contentHeavy12"
    let work = root.appendingPathComponent(label)
    let folder = work.appendingPathComponent("Selected")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var originals: [String: Data] = [:]
    if metadata {
      for index in 0..<100 {
        let ext = ["txt", "pdf", "png", "jpg", "zip"][index % 5]
        let name = "Download \(String(format: "%03d", index)) 2026-10-28.\(ext)"
        originals[name] = Data("ordinary metadata-only synthetic fixture".utf8)
      }
    } else {
      for (index, fixture) in fixtures.enumerated() {
        let ext = URL(fileURLWithPath: fixture.name).pathExtension
        originals["scan\(index).\(ext)"] = try fixture.bytes()
      }
    }
    for (name, bytes) in originals { try bytes.write(to: folder.appendingPathComponent(name)) }
    let bookmark = work.appendingPathComponent("settings/folder.bookmark")
    let start = ContinuousClock.now
    let coordinator = try await qualificationCoordinator(folder, bookmark: bookmark)
    do {
      let outcome = try await coordinator.planTask(
        request: metadata
          ? "Sort files by type" : "Give files readable names based on their contents"
      ) { system, user, limit in
        try await runtime.completeJSON(system: system, user: user, maximumOutputTokens: limit)
      }
      guard case .plan(let plan) = outcome else { throw LocalInferenceError.smokeCheckFailed }
      let result = try await coordinator.execute(plan)
      let elapsed = loadingTime + start.duration(to: .now)
      print(
        "QUAL \(label) planned=\(plan.changes.count) changed=\(result.changed.count) abstained=\(result.abstained.count) failed=\(result.failed.count) elapsedIncludingLoad=\(elapsed) load=\(loadingTime)"
      )
      if !result.changed.isEmpty {
        try await TaskCoordinator(bookmarkFile: bookmark).undoTask(plan.id)
      }
      for (name, bytes) in originals {
        guard try Data(contentsOf: folder.appendingPathComponent(name)) == bytes else {
          throw LocalInferenceError.smokeCheckFailed
        }
      }
      print("QUAL \(label) bytesAndReopenedUndo=pass")
      await reportMetrics(runtime)
      reportMemory("QUAL \(label)")
      return result.failed.isEmpty && result.unprocessed.isEmpty
        && (!metadata || (result.changed.count == 100 && elapsed < .seconds(60)))
    } catch {
      let intact = originals.allSatisfy { name, bytes in
        (try? Data(contentsOf: folder.appendingPathComponent(name))) == bytes
      }
      print(
        "QUAL \(label) FAILED errorCode=\(qualificationErrorCode(error)) originalsIntact=\(intact) elapsedIncludingLoad=\(loadingTime + start.duration(to: .now))"
      )
    }
    reportMemory("QUAL \(label)")
    return false
  }
}
