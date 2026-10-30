import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import TidyModel
import Tokenizers

public enum LocalInferenceError: Error {
  case notReady
  case busy
  case contextLimit
  case outputLimit
  case smokeCheckFailed
  case missingMetalResources
}

public struct LocalInferenceMetrics: Sendable {
  public let promptTokens: Int
  public let outputTokens: Int
  public let prefillSeconds: Double
  public let generationSeconds: Double
}

private struct NativeGeneration: Sendable {
  let text: String
  let metrics: LocalInferenceMetrics
}

/// Directory-only native inference. No Hub downloader, tools, guided-generation logging,
/// FoundationModels integration, or persistent prompt/output diagnostics are used.
public actor MLXLocalModelRuntime: LocalModelRuntime {
  private var container: ModelContainer?
  private var generation: Task<NativeGeneration, Error>?
  private var unloading = false
  private var loading = false
  public private(set) var lastMetrics: LocalInferenceMetrics?

  public init() {}

  public func loadAndCheck(directory: URL, commit: @Sendable () throws -> Void) async throws {
    guard !loading, !unloading else { throw LocalInferenceError.busy }
    loading = true
    defer { loading = false }
    if Bundle.main.bundleURL.pathExtension == "app" {
      guard let resources = Bundle.main.resourceURL else {
        throw LocalInferenceError.missingMetalResources
      }
      let metal = resources.appendingPathComponent(
        "mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib")
      guard FileManager.default.fileExists(atPath: metal.path) else {
        throw LocalInferenceError.missingMetalResources
      }
      // Do not rely on upstream's build-machine absolute-path fallback in a distributed app.
      GPU.metallib = metal
    }
    let loaded = try await LLMModelFactory.shared.loadContainer(
      from: directory, using: LocalTokenizerLoader())
    try Task.checkCancellation()
    let output = try await Self.generate(
      container: loaded,
      system: "Respond with exactly the requested JSON object. Do not add Markdown or commentary.",
      user: "Return exactly {\"status\":\"ready\"}.", maximumOutputTokens: 64)
    struct Check: Decodable { let status: String }
    guard let check = try? JSONDecoder().decode(Check.self, from: Data(output.text.utf8)),
      check.status == "ready"
    else {
      throw LocalInferenceError.smokeCheckFailed
    }
    try Task.checkCancellation()
    try commit()
    // Let an already-running task finish against its original container. New calls
    // still use that container while preparation runs; only the committed pointer changes.
    container = loaded
    lastMetrics = output.metrics
  }

  public func unload() async {
    let wasLoaded = container != nil || generation != nil
    unloading = true
    generation?.cancel()
    if let generation { _ = await generation.result }
    generation = nil
    container = nil
    lastMetrics = nil
    if wasLoaded { Memory.clearCache() }
    unloading = false
  }

  /// Complete, EOS-terminated text only; callers must parse and validate the entire envelope.
  /// Output is never itself an authorized plan and is never executed here.
  public func completeJSON(system: String, user: String, maximumOutputTokens: Int = 1024)
    async throws -> String
  {
    guard !unloading, generation == nil else { throw LocalInferenceError.busy }
    guard let container else { throw LocalInferenceError.notReady }
    let task = Task {
      try await Self.generate(
        container: container, system: system, user: user,
        maximumOutputTokens: maximumOutputTokens)
    }
    generation = task
    defer { generation = nil }
    let result = try await withTaskCancellationHandler {
      try await task.value
    } onCancel: {
      task.cancel()
    }
    lastMetrics = result.metrics
    return result.text
  }

  private static func generate(
    container: ModelContainer, system: String, user: String,
    maximumOutputTokens: Int
  ) async throws -> NativeGeneration {
    guard (1...2048).contains(maximumOutputTokens) else { throw LocalInferenceError.contextLimit }
    return try await container.perform { context in
      // TokenIterator pipelines asyncEval. Cancellation must drain Metal work before unloading.
      defer { Stream.gpu.synchronize() }
      try Task.checkCancellation()
      let tokens = try context.tokenizer.applyChatTemplate(messages: [
        ["role": "system", "content": system], ["role": "user", "content": user],
      ])
      // Never rotate/truncate away task metadata to fit an advertised enormous model context.
      guard tokens.count + maximumOutputTokens <= 8192 else {
        throw LocalInferenceError.contextLimit
      }
      let parameters = GenerateParameters(maxTokens: maximumOutputTokens + 1, temperature: 0)
      let started = Date.timeIntervalSinceReferenceDate
      var iterator = try TokenIterator(
        input: LMInput(tokens: MLXArray(tokens)), model: context.model,
        parameters: parameters)
      var output: [Int] = []
      var eos = Set(
        context.configuration.extraEOSTokens.compactMap { context.tokenizer.convertTokenToId($0) })
      if let id = context.tokenizer.eosTokenId { eos.insert(id) }
      while let token = iterator.next() {
        try Task.checkCancellation()
        if eos.contains(token) {
          return NativeGeneration(
            text: context.tokenizer.decode(tokenIds: output, skipSpecialTokens: true)
              .trimmingCharacters(in: .whitespacesAndNewlines),
            metrics: LocalInferenceMetrics(
              promptTokens: tokens.count, outputTokens: output.count,
              prefillSeconds: iterator.promptPrefillTime,
              generationSeconds: Date.timeIntervalSinceReferenceDate - started))
        }
        output.append(token)
        guard output.count <= maximumOutputTokens else { throw LocalInferenceError.outputLimit }
      }
      throw LocalInferenceError.outputLimit
    }
  }
}

private struct LocalTokenizerLoader: MLXLMCommon.TokenizerLoader {
  func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
    TokenizerAdapter(base: try await AutoTokenizer.from(modelFolder: directory))
  }
}

private struct TokenizerAdapter: MLXLMCommon.Tokenizer {
  let base: any Tokenizers.Tokenizer
  var bosToken: String? { base.bosToken }
  var eosToken: String? { base.eosToken }
  var unknownToken: String? { base.unknownToken }
  func encode(text: String, addSpecialTokens: Bool) -> [Int] {
    base.encode(text: text, addSpecialTokens: addSpecialTokens)
  }
  func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
    base.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
  }
  func convertTokenToId(_ token: String) -> Int? { base.convertTokenToId(token) }
  func convertIdToToken(_ id: Int) -> String? { base.convertIdToToken(id) }
  func applyChatTemplate(
    messages: [[String: any Sendable]], tools: [[String: any Sendable]]?,
    additionalContext: [String: any Sendable]?
  ) throws -> [Int] {
    try base.applyChatTemplate(
      messages: messages, tools: tools, additionalContext: additionalContext)
  }
}
