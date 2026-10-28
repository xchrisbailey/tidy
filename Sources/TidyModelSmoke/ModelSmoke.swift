import Darwin
import Foundation
import MLX
import TidyModel
import TidyModelRuntime

@main
struct ModelSmoke {
  @MainActor static func main() async throws {
    let runtime = MLXLocalModelRuntime()
    let root = URL.applicationSupportDirectory.appendingPathComponent(
      "Tidy/QualificationModels", isDirectory: true)
    let setup = ModelSetup(
      root: root, manifest: .qwenCandidate,
      transfer: URLSessionModelTransfer(), runtime: runtime)
    let started = ContinuousClock.now
    if CommandLine.arguments.contains("--download-approved") {
      await setup.download(consent: true)
    } else {
      await setup.restore()
    }
    guard setup.state == .ready else {
      print("Native setup did not reach ready: \(setup.state)")
      throw LocalInferenceError.notReady
    }
    print("Native verified load + readiness check seconds: \(started.duration(to: .now))")
    reportMemory("loaded")
    await reportMetrics(runtime)
    // Reuse the approved local qualification artifact, never download another copy.
    // A native activation/selection failure must leave the original runtime usable.
    do {
      try await runtime.loadAndCheck(directory: setup.modelDirectory) {
        throw CocoaError(.fileWriteNoPermission)
      }
      throw LocalInferenceError.smokeCheckFailed
    } catch let error as CocoaError where error.code == .fileWriteNoPermission {
      print("Native replacement rejected a failed selection commit")
    }
    let preparation = Task {
      try await runtime.loadAndCheck(directory: setup.modelDirectory)
    }
    try await Task.sleep(for: .milliseconds(25))
    preparation.cancel()
    do {
      try await preparation.value
      throw LocalInferenceError.smokeCheckFailed
    } catch is CancellationError {
      print("Native replacement preparation cancelled without unloading the working model")
    }
    let taskStart = ContinuousClock.now
    let result = try await runtime.completeJSON(
      system:
        "You plan file renames. Return only JSON: {\"operations\":[{\"sourceID\":\"f1\",\"destination\":\"Holiday.jpg\"}]}. No Markdown or commentary.",
      user:
        "Rename sourceID f1 (holiday.jpg) to Holiday.jpg. Preserve extension. Return the complete operation.",
      maximumOutputTokens: 256)
    struct Operation: Decodable, Equatable {
      let sourceID: String
      let destination: String
    }
    struct Envelope: Decodable { let operations: [Operation] }
    let envelope = try JSONDecoder().decode(Envelope.self, from: Data(result.utf8))
    guard envelope.operations == [.init(sourceID: "f1", destination: "Holiday.jpg")] else {
      throw LocalInferenceError.smokeCheckFailed
    }
    print(
      "Fixed synthetic rename smoke passed; operation count: \(envelope.operations.count); seconds: \(taskStart.duration(to: .now))"
    )
    reportMemory("after generation")
    await reportMetrics(runtime)
    let cancelled = Task {
      try await runtime.completeJSON(
        system: "Return only a JSON array of integers.",
        user: "List all integers from 1 to 1000 in order in one JSON array.",
        maximumOutputTokens: 2048)
    }
    try await Task.sleep(for: .milliseconds(50))
    let cancelStart = ContinuousClock.now
    cancelled.cancel()
    do {
      _ = try await cancelled.value
      throw LocalInferenceError.smokeCheckFailed
    } catch is CancellationError {
      print("Native generation cancellation quiesced in: \(cancelStart.duration(to: .now))")
    }
    // A cancelled decode must leave the model usable without retaining its KV cache.
    let recovered = try await runtime.completeJSON(
      system: "Return only JSON.",
      user: "Return exactly {\"status\":\"ready\"}.", maximumOutputTokens: 64)
    guard recovered.contains("\"ready\"") else { throw LocalInferenceError.smokeCheckFailed }
    print("Post-cancellation native inference passed")
    try await runtime.loadAndCheck(directory: setup.modelDirectory)
    let replaced = try await runtime.completeJSON(
      system: "Return only JSON.", user: "Return exactly {\"status\":\"ready\"}.",
      maximumOutputTokens: 64)
    guard replaced.contains("\"ready\"") else { throw LocalInferenceError.smokeCheckFailed }
    print("Native verified replacement and subsequent inference passed using the existing artifact")
    await runtime.unload()
  }

  static func reportMetrics(_ runtime: MLXLocalModelRuntime) async {
    if let metrics = await runtime.lastMetrics {
      print(
        "Native tokens: prompt=\(metrics.promptTokens) output=\(metrics.outputTokens) prefillSeconds=\(metrics.prefillSeconds) totalGenerationSeconds=\(metrics.generationSeconds)"
      )
    }
  }

  static func reportMemory(_ phase: String) {
    let memory = Memory.snapshot()
    var usage = rusage_info_v4()
    let status = withUnsafeMutablePointer(to: &usage) { pointer in
      pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
        proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
      }
    }
    print(
      "\(phase): MLX active=\(memory.activeMemory) cache=\(memory.cacheMemory) peak=\(memory.peakMemory) physicalFootprint=\(status == 0 ? usage.ri_phys_footprint : 0) bytes"
    )
  }
}
