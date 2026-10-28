import Darwin
import Foundation

public enum OperationState: String, Codable, Sendable {
  case intent, completed, undoIntent, undone, notApplied
}

public struct FileOperation: Codable, Sendable, Identifiable {
  public let id: UUID
  public let originalName: String
  public let destinationFolder: String
  public let selectedFolderPath: String
  public internal(set) var batchID: UUID? = nil
  public internal(set) var resultingName: String? = nil
  public var taskID: UUID { batchID ?? id }
  public var destinationName: String { resultingName ?? originalName }
  public internal(set) var state: OperationState
  let rootIdentity: FileIdentity
  let fileIdentity: FileIdentity
  var createdFolder: FileIdentity?
  var destinationIdentity: FileIdentity?
}

// Birth time supplements device/inode so a recycled inode is not accepted as the original file.
struct FileIdentity: Codable, Sendable, Equatable {
  let device: Int32
  let inode: UInt64
  let birthSeconds: Int64
  let birthNanoseconds: Int64

  init(_ info: stat) {
    device = info.st_dev
    inode = info.st_ino
    birthSeconds = Int64(info.st_birthtimespec.tv_sec)
    birthNanoseconds = Int64(info.st_birthtimespec.tv_nsec)
  }
}

struct FileSnapshot: Sendable, Equatable {
  let identity: FileIdentity
  let size: Int64
  let modifiedSeconds: Int64
  let modifiedNanoseconds: Int64
  let changedSeconds: Int64
  let changedNanoseconds: Int64
  let flags: UInt32
  let links: UInt16

  init(_ info: stat) {
    identity = FileIdentity(info)
    size = info.st_size
    modifiedSeconds = Int64(info.st_mtimespec.tv_sec)
    modifiedNanoseconds = Int64(info.st_mtimespec.tv_nsec)
    changedSeconds = Int64(info.st_ctimespec.tv_sec)
    changedNanoseconds = Int64(info.st_ctimespec.tv_nsec)
    flags = info.st_flags
    links = info.st_nlink
  }
}

public enum SortError: Error, LocalizedError, Equatable {
  case writeGrantRequired, unsupportedRequest, oneFileRequired, staleSource, conflict
  case uncertainIdentity, unavailable, journalUnavailable, busy
  case scopeTooLarge, confirmationRequired, invalidPlan
  case newerOperation

  public var errorDescription: String? {
    switch self {
    case .writeGrantRequired:
      "Select the folder with Grant Write Access before sorting or undoing. An old read grant is not write authorization."
    case .unsupportedRequest:
      "Only ‘Sort by type’ is supported in this slice. Broader requests are not available."
    case .oneFileRequired:
      "Sort by type currently requires exactly one eligible file with a supported type."
    case .staleSource:
      "The source changed or is missing. Refresh and try again. No overwrite was attempted."
    case .conflict: "The destination is occupied or unsafe. Nothing was overwritten."
    case .uncertainIdentity:
      "The recorded file or folder cannot be identified safely. Tidy stopped; check undo history before trying again."
    case .unavailable:
      "The filesystem operation could not finish. Refresh undo history to check the recorded result."
    case .journalUnavailable:
      "Undo history could not be saved or read. No further file changes were attempted."
    case .busy: "Another task or undo is running. Try again when it finishes."
    case .scopeTooLarge: "More than 1,000 eligible files. Choose a narrower folder."
    case .confirmationRequired:
      "Confirm the rename and move counts before changing more than 100 files."
    case .invalidPlan: "The plan is invalid or belongs to another folder. No files were changed."
    case .newerOperation:
      "A newer recorded change to this file blocks undo. Undo that newer task or file first; Tidy did not undo another task."
    }
  }
}

// The lock covers synchronous coordinator operations, including separate coordinator instances.
final class OperationJournal {
  let directory: URL
  let lock: Int32
  var file: URL { directory.appendingPathComponent("operations.json") }

  init(directory: URL) throws {
    self.directory = directory
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    lock = open(
      directory.appendingPathComponent("operations.lock").path,
      O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard lock >= 0 else { throw SortError.journalUnavailable }
    guard flock(lock, LOCK_EX | LOCK_NB) == 0 else {
      close(lock)
      throw SortError.busy
    }
  }

  deinit { close(lock) }

  func load() throws -> [FileOperation] {
    guard FileManager.default.fileExists(atPath: file.path) else { return [] }
    do {
      let entries = try JSONDecoder().decode([FileOperation].self, from: Data(contentsOf: file))
      guard
        entries.allSatisfy({ entry in
          validFileName(entry.originalName)
            && validFileName(entry.destinationName)
            && validDestinationFolder(entry.destinationFolder)
        }), Set(entries.map(\.id)).count == entries.count
      else { throw SortError.journalUnavailable }
      return entries
    } catch { throw SortError.journalUnavailable }
  }

  func save(_ entries: [FileOperation]) throws {
    try Self.persist(try JSONEncoder().encode(entries), to: file)
  }

  static func persist(_ data: Data, to file: URL) throws {
    let parent = file.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let temporary = parent.appendingPathComponent(".journal-\(UUID())")
    let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard fd >= 0 else { throw SortError.journalUnavailable }
    defer {
      close(fd)
      unlink(temporary.path)
    }
    try data.withUnsafeBytes { bytes in
      var offset = 0
      while offset < bytes.count {
        let count = write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
        guard count > 0 else { throw SortError.journalUnavailable }
        offset += count
      }
    }
    // Flush the new journal before publishing it, then flush its directory entry.
    guard fsync(fd) == 0, fcntl(fd, F_FULLFSYNC) == 0,
      rename(temporary.path, file.path) == 0
    else { throw SortError.journalUnavailable }
    let directoryFD = open(parent.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard directoryFD >= 0 else { throw SortError.journalUnavailable }
    defer { close(directoryFD) }
    guard fsync(directoryFD) == 0 else { throw SortError.journalUnavailable }
  }
}

final class ScopedDirectory {
  let url: URL
  let fd: Int32
  let identity: FileIdentity

  init(_ url: URL) throws {
    guard url.startAccessingSecurityScopedResource() else { throw SortError.writeGrantRequired }
    self.url = url
    fd = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    var info = stat()
    guard fd >= 0, fstat(fd, &info) == 0 else {
      if fd >= 0 { close(fd) }
      url.stopAccessingSecurityScopedResource()
      throw SortError.unavailable
    }
    identity = FileIdentity(info)
  }

  deinit {
    close(fd)
    url.stopAccessingSecurityScopedResource()
  }
}

func entryInfo(_ directory: Int32, _ name: String) -> stat? {
  var info = stat()
  return fstatat(directory, name, &info, AT_SYMLINK_NOFOLLOW) == 0 ? info : nil
}

func checkedEntryInfo(_ directory: Int32, _ name: String) throws -> stat? {
  var info = stat()
  if fstatat(directory, name, &info, AT_SYMLINK_NOFOLLOW) == 0 { return info }
  guard errno == ENOENT else { throw SortError.unavailable }
  return nil
}

func pinFile(_ parent: Int32, _ name: String, identity: FileIdentity) throws -> Int32 {
  let fd = openat(parent, name, O_EVTONLY | O_NOFOLLOW | O_CLOEXEC)
  guard fd >= 0 else { throw SortError.uncertainIdentity }
  var info = stat()
  guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
    info.st_nlink == 1, FileIdentity(info) == identity
  else {
    close(fd)
    throw SortError.uncertainIdentity
  }
  return fd
}

func childDirectory(_ parent: Int32, _ name: String) throws -> Int32 {
  let fd = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
  guard fd >= 0 else { throw SortError.conflict }
  return fd
}

func moveExclusive(
  _ source: Int32, _ name: String, _ destination: Int32, as resultingName: String? = nil
) throws {
  guard renameatx_np(source, name, destination, resultingName ?? name, UInt32(RENAME_EXCL)) == 0
  else {
    throw errno == EEXIST ? SortError.conflict : SortError.unavailable
  }
  guard fsync(source) == 0, fsync(destination) == 0 else { throw SortError.unavailable }
}

func validFileName(_ name: String) -> Bool {
  !name.isEmpty && name.utf8.count <= Int(NAME_MAX)
    && !name.contains("/") && !name.contains("\0") && ![".", ".."].contains(name)
}

func directoryNames(_ directory: Int32) throws -> Set<String> {
  let copy = dup(directory)
  guard copy >= 0 else { throw SortError.unavailable }
  guard let stream = fdopendir(copy) else {
    close(copy)
    throw SortError.unavailable
  }
  defer { closedir(stream) }
  var names: Set<String> = []
  while true {
    errno = 0
    guard let entry = readdir(stream) else {
      guard errno == 0 else { throw SortError.unavailable }
      return names
    }
    let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
      pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) {
        String(cString: $0)
      }
    }
    names.insert(name.lowercased())
  }
}
