import Foundation

public let inspectionServiceName = "dev.tidy.inspection"

@objc public protocol InspectionServiceProtocol {
  func inspectPDF(_ input: Data, requestID: String, withReply reply: @escaping (Data) -> Void)
  func cancel(_ requestID: String, withReply reply: @escaping () -> Void)
}

public struct InspectionReply: Codable, Sendable {
  public let code: String
  public var text: String
  public var coverage: String

  public init(code: String, text: String = "", coverage: String = "") {
    self.code = code
    self.text = text
    self.coverage = coverage
  }
}

public enum WorkerFailure: String, Error {
  case unavailable, unreadable, inputLimit, deadline, cancelled
}
