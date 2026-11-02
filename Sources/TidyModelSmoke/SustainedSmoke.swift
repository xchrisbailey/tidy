import Foundation
import TidyModelRuntime

extension ModelSmoke {
  @MainActor static func qualificationSustained(
    _ runtime: MLXLocalModelRuntime, modelDirectory: URL
  ) async throws {
    try requireOfflineNetworkDenial()
    guard let corpus = Bundle.module.url(forResource: "QualificationCorpus", withExtension: "json")
    else { throw LocalInferenceError.smokeCheckFailed }
    let fixtures = try JSONDecoder().decode(
      [QualificationFixture].self, from: Data(contentsOf: corpus))
    let content = Array(fixtures.filter(\.eligible).prefix(12))
    guard content.count == 12 else { throw LocalInferenceError.smokeCheckFailed }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "tidy-sustained-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let started = ContinuousClock.now
    var maximumGap = Duration.zero
    var ticks = 0
    let heartbeat = Task { @MainActor in
      var previous = ContinuousClock.now
      while !Task.isCancelled {
        do { try await Task.sleep(for: .milliseconds(100)) } catch { break }
        let now = ContinuousClock.now
        maximumGap = max(maximumGap, previous.duration(to: now))
        previous = now
        ticks += 1
      }
    }
    defer { heartbeat.cancel() }
    for round in 1...20 {
      let work = root.appendingPathComponent("round-\(round)")
      let begin = ContinuousClock.now
      guard
        try await qualificationBatch(
          runtime, root: work, fixtures: [], loadingTime: .zero, expectedChanges: 100),
        try await qualificationBatch(
          runtime, root: work, fixtures: content, loadingTime: .zero, expectedChanges: 12)
      else { throw LocalInferenceError.smokeCheckFailed }
      print(
        "SUSTAINED round=\(round) metadata=100 content=12 bytesAndReopenedUndo=pass elapsed=\(begin.duration(to: .now))"
      )
      reportMemory("SUSTAINED round=\(round)")
      // Periodic unloading checks reuse of the same approved artifact, not replacement
      // between production revisions or behavior under induced memory pressure.
      if round.isMultiple(of: 5) {
        await runtime.unload()
        reportMemory("SUSTAINED round=\(round) unloaded")
        if round < 20 {
          try await runtime.loadAndCheck(directory: modelDirectory)
          reportMemory("SUSTAINED round=\(round) reloaded")
        }
      }
    }
    heartbeat.cancel()
    await heartbeat.value
    print(
      "SUSTAINED PASS rounds=20 metadataChanges=2000 contentChanges=240 elapsed=\(started.duration(to: .now)) heartbeatTicks=\(ticks) maximumMainActorGap=\(maximumGap); not native UI, pressure, leak-proof or minimum-hardware evidence"
    )
  }
}
