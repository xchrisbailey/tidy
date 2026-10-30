import Foundation

public enum DiagnosticCode: String, Sendable {
  case modelFailure, modelUnavailable, invalidPlan, taskFailure, interrupted, recoveryFailure
}

public enum DiagnosticModelState: String, Encodable, Sendable {
  case unknown, ready, failed, unavailable, notReady, busy, paused, cancelled
}

public enum DiagnosticExportError: Error, LocalizedError {
  case couldNotSave
  public var errorDescription: String? {
    "Diagnostics could not be saved. Choose another location and try again. Nothing was sent."
  }
}

// Only this closed schema reaches disk. Never accept arbitrary error strings, metadata or outcomes.
private struct DiagnosticArtifact: Encodable {
  let schemaVersion = 1
  let platform: Platform
  let counters: [String: Int]
  let modelState: DiagnosticModelState

  struct Platform: Encodable {
    let macOSMajor: Int
    let macOSMinor: Int
    let macOSPatch: Int
  }
}

extension TaskCoordinator {
  /// Session-only fixed-code counters. Never pass error descriptions or model setup reason text.
  public func recordDiagnostic(_ code: DiagnosticCode) {
    diagnosticCounters[code] = min(1_000_000, diagnosticCounters[code, default: 0] + 1)
  }

  func recordInspectionCodes(_ outcomes: [FileOutcome]) {
    for outcome in outcomes {
      if let code = outcome.inspectionCode {
        inspectionDiagnosticCounters[code] = min(
          1_000_000, inspectionDiagnosticCounters[code, default: 0] + 1)
      }
    }
  }

  /// Explicit local export only. Neither the destination nor write errors enter diagnostics.
  public func exportDiagnostics(
    to destination: URL, modelState: DiagnosticModelState = .unknown
  ) throws {
    var counters = Dictionary(
      uniqueKeysWithValues: diagnosticCounters.map { ($0.key.rawValue, $0.value) })
    for (code, count) in inspectionDiagnosticCounters {
      counters["inspection_" + code.rawValue] = count
    }
    // Observe durable state without reconciling, exporting identities or resuming any work.
    do {
      let snapshot = try historySnapshot()
      for operation in snapshot.operations {
        let key = "history_" + operation.state.rawValue
        counters[key] = min(1_000_000, counters[key, default: 0] + 1)
      }
    } catch {
      counters["historyUnavailable"] = 1
    }
    let version = ProcessInfo.processInfo.operatingSystemVersion
    let artifact = DiagnosticArtifact(
      platform: .init(
        macOSMajor: version.majorVersion, macOSMinor: version.minorVersion,
        macOSPatch: version.patchVersion), counters: counters, modelState: modelState)
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try encoder.encode(artifact).write(to: destination, options: [.atomic])
    } catch {
      throw DiagnosticExportError.couldNotSave
    }
  }
}
