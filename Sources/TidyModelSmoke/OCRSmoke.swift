import CoreGraphics
import CoreText
import Foundation
import ImageIO
import TidyModelRuntime

extension ModelSmoke {
  static func ocrNamingSmoke(_ runtime: MLXLocalModelRuntime) async throws {
    try requireOfflineNetworkDenial()
    for format in ["png", "pdf"] {
      if let example = CommandLine.arguments.first(where: { $0.hasPrefix("--ocr-example=") }),
        example != "--ocr-example=\(format)"
      {
        continue
      }
      try await pdfNamingExample(
        runtime, label: "OCR-\(format)",
        lines: [
          "Acme Invoice AB123 2026-10-28",
          "This invoice covers professional services provided during October.",
          "Payment is due by bank transfer.",
        ], required: ["Acme", "Invoice", "AB123", "2026-10-28"], ocrFormat: format)
    }
    if let example = CommandLine.arguments.first(where: { $0.hasPrefix("--ocr-example=") }),
      example != "--ocr-example=spanish"
    {
      return
    }
    try await pdfNamingExample(
      runtime, label: "OCR-spanish",
      lines: [
        "Factura Iberia CD456 2026-09-15",
        "Esta factura corresponde a los servicios prestados durante octubre.",
        "El pago se realizará mediante transferencia bancaria.",
      ], required: ["Factura", "Iberia", "CD456", "2026-09-15"], ocrFormat: "png")
  }

  static func syntheticOCR(_ lines: [String], scanned: Bool) throws -> Data {
    guard
      let context = CGContext(
        data: nil, width: 1600, height: 600,
        bitsPerComponent: 8, bytesPerRow: 1600 * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { throw LocalInferenceError.smokeCheckFailed }
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 1600, height: 600))
    for (index, text) in lines.enumerated() {
      let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(
          "Helvetica" as CFString, 36, nil),
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(
          gray: 0, alpha: 1),
      ]
      let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: text, attributes: attributes))
      context.textPosition = CGPoint(x: 50, y: 500 - index * 60)
      CTLineDraw(line, context)
    }
    guard let image = context.makeImage() else { throw LocalInferenceError.smokeCheckFailed }
    let bytes = NSMutableData()
    if scanned {
      var box = CGRect(x: 0, y: 0, width: 800, height: 300)
      guard let consumer = CGDataConsumer(data: bytes),
        let pdf = CGContext(consumer: consumer, mediaBox: &box, nil)
      else { throw LocalInferenceError.smokeCheckFailed }
      pdf.beginPDFPage(nil)
      pdf.draw(image, in: box)
      pdf.endPDFPage()
      pdf.closePDF()
    } else {
      guard
        let destination = CGImageDestinationCreateWithData(bytes, "public.png" as CFString, 1, nil)
      else { throw LocalInferenceError.smokeCheckFailed }
      CGImageDestinationAddImage(destination, image, nil)
      guard CGImageDestinationFinalize(destination) else {
        throw LocalInferenceError.smokeCheckFailed
      }
    }
    return bytes as Data
  }
}
