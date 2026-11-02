import Darwin
import Foundation

@main
struct IdentityTestWorker {
  static func main() {
    alarm(10)
    do {
      guard CommandLine.arguments.count == 3, CommandLine.arguments[1] == "capture" else {
        throw CaptureError.invalidArguments
      }
      let capture = try capture(CommandLine.arguments[2])
      try FileHandle.standardOutput.write(contentsOf: JSONEncoder().encode(capture))
    } catch {
      FileHandle.standardError.write(Data("Identity capture failed: \(error)\n".utf8))
      exit(2)
    }
  }

  private static func capture(_ path: String) throws -> Capture {
    var entry = stat()
    guard lstat(path, &entry) == 0 else { throw CaptureError.system("lstat", errno) }
    guard entry.st_mode & S_IFMT == S_IFREG || entry.st_mode & S_IFMT == S_IFDIR,
      entry.st_flags & UInt32(SF_DATALESS) == 0
    else { throw CaptureError.ineligible }
    let fd = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
    guard fd >= 0 else { throw CaptureError.system("open", errno) }
    defer { close(fd) }
    var before = stat()
    guard fstat(fd, &before) == 0 else { throw CaptureError.system("fstat", errno) }
    guard before.st_dev == entry.st_dev, before.st_ino == entry.st_ino,
      before.st_mode & S_IFMT == entry.st_mode & S_IFMT,
      before.st_flags & UInt32(SF_DATALESS) == 0
    else {
      throw CaptureError.changed
    }

    var object = try attributes(fd, common: UInt32(ATTR_CMN_FILEID), volume: 0)
    let fileID: UInt64 = try object.read()
    try object.finish()

    var volume = try attributes(
      fd, common: 0,
      volume: ATTR_VOL_INFO | UInt32(ATTR_VOL_CAPABILITIES) | UInt32(ATTR_VOL_UUID))
    let supported: UInt32 = try volume.read()
    for _ in 0..<3 { let _: UInt32 = try volume.read() }
    let valid: UInt32 = try volume.read()
    for _ in 0..<3 { let _: UInt32 = try volume.read() }
    let uuidBytes = try volume.bytes(count: 16)
    try volume.finish()
    let uuid =
      uuidBytes.contains(where: { $0 != 0 })
      ? uuidBytes.map { String(format: "%02x", $0) }.joined() : nil
    let pathFromIDValid = valid & UInt32(VOL_CAP_FMT_PATH_FROM_ID) != 0
    let pathFromIDSupported = supported & UInt32(VOL_CAP_FMT_PATH_FROM_ID) != 0
    var after = stat()
    guard fstat(fd, &after) == 0 else { throw CaptureError.system("fstat", errno) }
    guard after.st_dev == before.st_dev, after.st_ino == before.st_ino,
      after.st_mode & S_IFMT == before.st_mode & S_IFMT,
      after.st_flags & UInt32(SF_DATALESS) == 0,
      after.st_birthtimespec.tv_sec == before.st_birthtimespec.tv_sec,
      after.st_birthtimespec.tv_nsec == before.st_birthtimespec.tv_nsec,
      fileID == after.st_ino
    else { throw CaptureError.changed }
    return Capture(
      fileID: fileID, volumeUUID: uuid, formatSupported: supported, formatValid: valid,
      pathFromIDSupported: pathFromIDSupported, pathFromIDValid: pathFromIDValid,
      documentedCapabilityCandidate: pathFromIDValid && pathFromIDSupported && uuid != nil
        && fileID != 0,
      birthSeconds: Int64(after.st_birthtimespec.tv_sec),
      birthNanoseconds: Int64(after.st_birthtimespec.tv_nsec))
  }

  private static func attributes(_ fd: Int32, common: UInt32, volume: UInt32) throws
    -> AttributeBuffer
  {
    var requested = attrlist()
    requested.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
    requested.commonattr = common | UInt32(ATTR_CMN_RETURNED_ATTRS)
    requested.volattr = volume
    var data = Data(count: 4096)
    let result = data.withUnsafeMutableBytes { bytes in
      fgetattrlist(fd, &requested, bytes.baseAddress, bytes.count, 0)
    }
    guard result == 0 else { throw CaptureError.system("fgetattrlist", errno) }
    var buffer = AttributeBuffer(data: data)
    let length: UInt32 = try buffer.read()
    guard length >= 24, length <= data.count else { throw CaptureError.invalidAttributes }
    buffer.limit = Int(length)
    let returnedCommon: UInt32 = try buffer.read()
    let returnedVolume: UInt32 = try buffer.read()
    let returnedDirectory: UInt32 = try buffer.read()
    let returnedFile: UInt32 = try buffer.read()
    let returnedFork: UInt32 = try buffer.read()
    // Reject omitted/unknown fields rather than decoding a different packed layout.
    guard returnedCommon == requested.commonattr,
      returnedVolume == requested.volattr & ~ATTR_VOL_INFO,
      returnedDirectory == 0, returnedFile == 0, returnedFork == 0
    else { throw CaptureError.unavailableAttributes }
    return buffer
  }
}

private struct Capture: Encodable {
  let fileID: UInt64
  let volumeUUID: String?
  let formatSupported: UInt32
  let formatValid: UInt32
  let pathFromIDSupported: Bool
  let pathFromIDValid: Bool
  let documentedCapabilityCandidate: Bool
  let birthSeconds: Int64
  let birthNanoseconds: Int64
}

private struct AttributeBuffer {
  let data: Data
  var offset = 0
  var limit = 4096

  mutating func read<Value: FixedWidthInteger>() throws -> Value {
    let size = MemoryLayout<Value>.size
    guard offset <= limit - size else { throw CaptureError.invalidAttributes }
    let value = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: Value.self) }
    offset += size
    return value
  }

  mutating func bytes(count: Int) throws -> Data {
    guard count >= 0, offset <= limit - count else { throw CaptureError.invalidAttributes }
    defer { offset += count }
    return data.subdata(in: offset..<(offset + count))
  }

  func finish() throws {
    guard offset == limit else { throw CaptureError.invalidAttributes }
  }
}

private enum CaptureError: Error {
  case invalidArguments, ineligible, changed, invalidAttributes, unavailableAttributes
  case system(String, Int32)
}
