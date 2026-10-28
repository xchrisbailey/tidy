import Foundation

public struct URLSessionModelTransfer: ModelTransfer {
  private let allowLoopbackHTTP: Bool

  public init(allowLoopbackHTTP: Bool = false) { self.allowLoopbackHTTP = allowLoopbackHTTP }

  public func download(_ file: ModelFile, to destination: URL, resumeFile: URL) async throws {
    guard permits(file.url) else { throw URLError(.unsupportedURL) }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.httpCookieStorage = nil
    configuration.urlCredentialStorage = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.timeoutIntervalForResource = 24 * 60 * 60
    do {
      if let resume = try? Data(contentsOf: resumeFile), !resume.isEmpty {
        do {
          try await DownloadOperation(
            file: file, destination: destination, resumeFile: resumeFile,
            allowLoopbackHTTP: allowLoopbackHTTP
          ).run(configuration: configuration, resume: resume)
        } catch {
          try Task.checkCancellation()
          // Resume data is best effort and can outlive the OS's temporary file.
          // Restart just this file, never append an unchecked Range response.
          try discardResumeFile(resumeFile)
          try await DownloadOperation(
            file: file, destination: destination, resumeFile: resumeFile,
            allowLoopbackHTTP: allowLoopbackHTTP
          ).run(configuration: configuration, resume: nil)
        }
      } else {
        try await DownloadOperation(
          file: file, destination: destination, resumeFile: resumeFile,
          allowLoopbackHTTP: allowLoopbackHTTP
        ).run(configuration: configuration, resume: nil)
      }
      try Task.checkCancellation()
      try ModelStorage.removeIfPresent(resumeFile)
    } catch {
      let nsError = error as NSError
      if let resume = nsError.userInfo["NSURLSessionDownloadTaskResumeData"] as? Data {
        try resume.write(to: resumeFile, options: .atomic)
      }
      throw error
    }
  }

  public func discardPartials(in directory: URL) async throws {
    guard FileManager.default.fileExists(atPath: directory.path) else { return }
    for file in try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil)
    where file.pathExtension == "resume" {
      try discardResumeFile(file)
    }
  }

  private func permits(_ url: URL) -> Bool {
    url.scheme == "https" || (allowLoopbackHTTP && url.scheme == "http" && url.host == "127.0.0.1")
  }

  private func discardResumeFile(_ file: URL) throws {
    if let data = try? Data(contentsOf: file),
      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
      let dictionary = plist as? [String: Any],
      let name = dictionary["NSURLSessionResumeInfoTempFileName"] as? String,
      !name.isEmpty, name == URL(fileURLWithPath: name).lastPathComponent,
      name.hasPrefix("CFNetworkDownload_")
    {
      let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(name)
      try ModelStorage.removeIfPresent(temporary)
    }
    try ModelStorage.removeIfPresent(file)
  }
}

/// URLSession's async download convenience cancels without producing resume data.
/// This bridge returns only after didComplete AND the explicit cancellation callback.
private final class DownloadOperation: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
  private let file: ModelFile
  private let destination: URL
  private let resumeFile: URL
  private let allowLoopbackHTTP: Bool
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Void, any Error>?
  private var task: URLSessionDownloadTask?
  private var session: URLSession?
  private var cancelled = false
  private var completed = false
  private var resumeCallbackReceived = false
  private var resumeData: Data?
  private var failure: (any Error)?

  init(file: ModelFile, destination: URL, resumeFile: URL, allowLoopbackHTTP: Bool) {
    self.file = file
    self.destination = destination
    self.resumeFile = resumeFile
    self.allowLoopbackHTTP = allowLoopbackHTTP
  }

  func run(configuration: URLSessionConfiguration, resume: Data?) async throws {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        let task =
          resume.map { session.downloadTask(withResumeData: $0) }
          ?? session.downloadTask(with: URLRequest(url: file.url))
        let alreadyCancelled = lock.withLock {
          self.continuation = continuation
          self.session = session
          self.task = task
          return cancelled
        }
        task.resume()
        if alreadyCancelled { cancelTask(task) }
      }
    } onCancel: {
      let task = self.lock.withLock {
        self.cancelled = true
        return self.task
      }
      if let task { self.cancelTask(task) }
    }
  }

  private func cancelTask(_ task: URLSessionDownloadTask) {
    task.cancel { data in
      self.lock.withLock {
        self.resumeData = data ?? self.resumeData
        self.resumeCallbackReceived = true
      }
      self.finishIfQuiescent()
    }
  }

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    lock.withLock {
      guard !cancelled else { return }
      do {
        guard let response = downloadTask.response as? HTTPURLResponse,
          [200, 206].contains(response.statusCode), let url = response.url,
          url.scheme == "https"
            || (allowLoopbackHTTP && url.scheme == "http" && url.host == "127.0.0.1")
        else { throw URLError(.badServerResponse) }
        let size = try location.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard let size, Int64(size) == file.bytes else { throw ModelStorageError.integrity }
        try ModelStorage.removeIfPresent(destination)
        try FileManager.default.moveItem(at: location, to: destination)
      } catch { failure = error }
    }
  }

  func urlSession(
    _ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?
  ) {
    lock.withLock {
      completed = true
      if let error {
        failure = error
        resumeData =
          (error as NSError).userInfo["NSURLSessionDownloadTaskResumeData"] as? Data ?? resumeData
      }
    }
    finishIfQuiescent()
  }

  private func finishIfQuiescent() {
    let finished: (CheckedContinuation<Void, any Error>, (any Error)?, URLSession?)? = lock.withLock
    {
      guard completed, !cancelled || resumeCallbackReceived, let continuation else { return nil }
      var error: (any Error)? = cancelled ? CancellationError() : failure
      if let resumeData {
        do { try resumeData.write(to: resumeFile, options: .atomic) } catch let writeError {
          error = writeError
        }
      }
      self.continuation = nil
      self.task = nil
      let session = self.session
      self.session = nil
      return (continuation, error, session)
    }
    guard let (continuation, error, session) = finished else { return }
    session?.finishTasksAndInvalidate()
    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
  }

  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    guard let url = request.url,
      url.scheme == "https"
        || (allowLoopbackHTTP && url.scheme == "http" && url.host == "127.0.0.1")
    else {
      completionHandler(nil)
      return
    }
    completionHandler(request)
  }
}
