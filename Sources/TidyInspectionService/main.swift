import Darwin
import Foundation
import TidyInspection

@_silgen_name("sandbox_init")
private func restrictProcess(
  _ profile: UnsafePointer<CChar>, _ flags: UInt64,
  _ error: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> Int32

// All mutable request state is protected by this lock; the XPC delivery queue can cancel while
// the worker queue is supervising a synchronous native parser in another process.
final class Request: @unchecked Sendable {
  private let lock = NSLock()
  private var stopped = false
  func cancel() {
    lock.lock()
    stopped = true
    lock.unlock()
  }
  var cancelled: Bool {
    lock.lock()
    defer { lock.unlock() }
    return stopped
  }
}

final class Service: NSObject, InspectionServiceProtocol, @unchecked Sendable {
  let queue = DispatchQueue(label: "dev.tidy.inspection.worker")
  private let lock = NSLock()
  private var request: (String, Request)?

  func inspectDocument(
    _ input: Data, format: String, requestID: String, withReply reply: @escaping (Data) -> Void
  ) {
    lock.lock()
    guard request == nil, UUID(uuidString: requestID) != nil, input.count <= 20 * 1024 * 1024,
      ["pdf", "png", "jpg", "jpeg", "heic", "heif", "tif", "tiff"].contains(format)
    else {
      lock.unlock()
      reply(Self.encoded("inputLimit"))
      return
    }
    let state = Request()
    request = (requestID, state)
    lock.unlock()
    // NSXPC reply blocks are thread-safe but not annotated Sendable in the macOS 14 interface.
    let callback = Callback(reply)
    queue.async {
      let process = Process()
      process.executableURL = Bundle.main.bundleURL.appendingPathComponent(
        "Contents/Helpers/TidyInspectionHelper")
      process.arguments = ["--format=\(format)", "--inherited-containment"]
      let output: Data
      do {
        output = try WorkerSupervisor.run(
          input, process: process, deadline: .now.advanced(by: .seconds(3)),
          errorOutput: errorSink,
          cancelled: { state.cancelled })
      } catch let error as WorkerFailure { output = Self.encoded(error.rawValue) } catch {
        output = Self.encoded("unreadable")
      }
      self.lock.lock()
      self.request = nil
      self.lock.unlock()
      callback.call(output)
    }
  }

  func cancel(_ requestID: String, withReply reply: @escaping () -> Void) {
    lock.lock()
    if request?.0 == requestID { request?.1.cancel() }
    lock.unlock()
    let callback = Callback { _ in reply() }
    // This acknowledgement occurs only after the supervisor has killed/reaped the worker.
    queue.async { callback.call(Data()) }
  }

  func disconnect() {
    lock.lock()
    request?.1.cancel()
    lock.unlock()
  }

  static func encoded(_ code: String) -> Data {
    (try? JSONEncoder().encode(InspectionReply(code: code))) ?? Data()
  }
}

final class Callback: @unchecked Sendable {
  let body: (Data) -> Void
  init(_ body: @escaping (Data) -> Void) { self.body = body }
  func call(_ data: Data) { body(data) }
}

final class Delegate: NSObject, NSXPCListenerDelegate {
  func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection)
    -> Bool
  {
    let service = Service()
    connection.exportedInterface = NSXPCInterface(with: InspectionServiceProtocol.self)
    connection.exportedObject = service
    connection.invalidationHandler = { service.disconnect() }
    connection.interruptionHandler = { service.disconnect() }
    connection.resume()
    return true
  }
}

func escaped(_ value: String) -> String {
  value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
}

// XPC is independently launched, NOT an inherited NSTask sandbox. Install strict restrictions
// before accepting any input. No App Sandbox inheritance/network/bookmark/container entitlement.
let bundle = Bundle.main.bundleURL.path
let errorSink = FileHandle.nullDevice
_ = errorSink.fileDescriptor
let worker = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/TidyInspectionHelper")
  .path
var core = rlimit(rlim_cur: 0, rlim_max: 0)
guard setrlimit(RLIMIT_CORE, &core) == 0 else { exit(1) }
let profile = """
  (version 1) (allow default) (deny network*) (deny file-write*) (deny file-read*)
  (deny process-exec)
  (allow process-exec (literal "\(escaped(worker))"))
  (allow file-read-data (literal "/"))
  (allow file-read* (subpath "/System") (subpath "/usr/lib") (subpath "\(escaped(bundle))"))
  (allow file-read* file-write* (literal "/dev/null"))
  """
guard profile.withCString({ restrictProcess($0, 0, nil) }) == 0 else { exit(1) }
let delegate = Delegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
