import Foundation

enum ImageFraming {
  static func isComplete(_ input: Data, format: String) -> Bool {
    input.withUnsafeBytes { bytes in
      switch format {
      case "png": completePNG(bytes)
      case "jpg", "jpeg": completeJPEG(bytes)
      default: true
      }
    }
  }

  private static func completePNG(_ bytes: UnsafeRawBufferPointer) -> Bool {
    let signature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
    guard bytes.count >= 8, bytes.prefix(8).elementsEqual(signature) else { return false }
    var offset = 8
    var hasImageData = false
    while offset <= bytes.count - 12 {
      let length = Int(
        UInt32(bigEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self)))
      let type = UInt32(bigEndian: bytes.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self))
      guard length <= bytes.count - offset - 12 else { return false }
      if offset == 8 {
        guard type == 0x4948_4452, length == 13 else { return false }
      } else if type == 0x4948_4452 {
        return false
      }
      if type == 0x4944_4154 { hasImageData = true }
      if type == 0x4945_4E44 { return length == 0 && hasImageData }
      offset += length + 12
    }
    return false
  }

  private static func completeJPEG(_ bytes: UnsafeRawBufferPointer) -> Bool {
    guard bytes.count >= 4, bytes[0] == 0xff, bytes[1] == 0xd8 else { return false }
    var offset = 2
    var hasScan = false
    while offset < bytes.count {
      guard bytes[offset] == 0xff else { return false }
      while offset < bytes.count, bytes[offset] == 0xff { offset += 1 }
      guard offset < bytes.count else { return false }
      let marker = bytes[offset]
      offset += 1
      if marker == 0xd9 { return hasScan }
      if marker == 0x01 { continue }
      guard marker != 0x00, marker != 0xd8, !(0xd0...0xd7).contains(marker),
        offset <= bytes.count - 2
      else { return false }
      let length = Int(bytes[offset]) * 256 + Int(bytes[offset + 1])
      guard length >= 2, length <= bytes.count - offset else { return false }
      offset += length
      guard marker == 0xda else { continue }
      hasScan = true
      // Metadata can contain embedded end markers. Only scan bytes use byte
      // stuffing/restart markers; subsequent scans return to segment parsing.
      while offset < bytes.count {
        if bytes[offset] != 0xff {
          offset += 1
          continue
        }
        let start = offset
        while offset < bytes.count, bytes[offset] == 0xff { offset += 1 }
        guard offset < bytes.count else { return false }
        let next = bytes[offset]
        if next == 0x00 || next == 0x01 || (0xd0...0xd7).contains(next) {
          offset += 1
        } else {
          offset = start
          break
        }
      }
    }
    return false
  }
}
