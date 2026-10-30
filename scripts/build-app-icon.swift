import AppKit
import Foundation

// Keep the approved artwork intact; clip its opaque corners onto a padded macOS tile.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let icons = root.appendingPathComponent("Packaging/Icons")
let source = icons.appendingPathComponent("Tidy-source.png")
guard let image = NSImage(contentsOf: source) else {
  fatalError("Cannot load approved icon artwork")
}
let temporary = FileManager.default.temporaryDirectory
  .appendingPathComponent("tidy-icon-\(UUID().uuidString)")
let iconset = temporary.appendingPathComponent("Tidy.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temporary) }

for points in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let pixels = points * scale
    guard
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: bitmap)
    else { fatalError("Cannot create icon bitmap") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let size = CGFloat(pixels)
    let tile = NSRect(x: size / 16, y: size / 16, width: size * 7 / 8, height: size * 7 / 8)
    NSBezierPath(roundedRect: tile, xRadius: size * 0.21, yRadius: size * 0.21).addClip()
    image.draw(in: tile, from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
      fatalError("Cannot encode icon bitmap")
    }
    let suffix = scale == 2 ? "@2x" : ""
    try png.write(to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    if pixels == 1024 {
      try png.write(to: icons.appendingPathComponent("Tidy.png"))
    }
  }
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = [
  "--convert", "icns", "--output", icons.appendingPathComponent("Tidy.icns").path, iconset.path,
]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Generated Packaging/Icons/Tidy.icns and Tidy.png")
