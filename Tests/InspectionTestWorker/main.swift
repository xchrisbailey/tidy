import Darwin
import Foundation

var mode = CommandLine.arguments.last ?? ""
if mode == "--inherited-containment" {
  let bytes = (try? FileHandle.standardInput.read(upToCount: 128)) ?? Data()
  mode = String(decoding: bytes, as: UTF8.self).split(separator: " ").last.map(String.init) ?? ""
}
switch mode {
case "count":
  var count = 0
  while let chunk = try FileHandle.standardInput.read(upToCount: 4096), !chunk.isEmpty {
    count += chunk.count
  }
  try FileHandle.standardOutput.write(contentsOf: Data(String(count).utf8))
case "hang", "cancel", "disconnect":
  raise(SIGSTOP)
case "crash":
  raise(SIGKILL)
  _exit(23)
case "oversize":
  try? FileHandle.standardOutput.write(contentsOf: Data(repeating: 65, count: 200_000))
case "malformed":
  try? FileHandle.standardOutput.write(contentsOf: Data("{}".utf8))
case "badText":
  try? FileHandle.standardOutput.write(
    contentsOf: Data(
      #"{"code":"ok","text":"Acme Invoice\u0000","coverage":"wholeDocument"}"#.utf8))
case "containment":
  let source = open("/etc/passwd", O_RDONLY)
  let readDenied = source < 0 && errno == EPERM
  if source >= 0 { close(source) }
  let path = "/private/tmp/tidy-inspection-probe-\(UUID())"
  let destination = open(path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
  let writeDenied = destination < 0 && errno == EPERM
  if destination >= 0 {
    close(destination)
    unlink(path)
  }
  let network = socket(AF_INET, SOCK_STREAM, 0)
  var networkDenied = network < 0 && errno == EPERM
  if network >= 0 {
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = UInt16(9).bigEndian
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    let result = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(network, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    networkDenied = result < 0 && errno == EPERM
    close(network)
  }
  let code = readDenied && writeDenied && networkDenied ? "ok" : "unavailable"
  try? FileHandle.standardOutput.write(
    contentsOf: Data(
      """
      {"code":"\(code)","text":"Acme Invoice AB123 2026-10-28","coverage":"wholeDocument","kind":"pdfText"}
      """.utf8))
default:
  try? FileHandle.standardOutput.write(contentsOf: Data("ok".utf8))
}
