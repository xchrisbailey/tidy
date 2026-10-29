import Foundation

// Translation is deliberately constrained to grounded document descriptors. Unqualified free
// translation cannot independently establish that a generated entity or document purpose is true.
private let descriptors: [[String: String]] = [
  [
    "en": "Invoice", "es": "Factura", "fr": "Facture", "de": "Rechnung", "it": "Fattura",
    "pt": "Fatura",
  ],
  [
    "en": "Receipt", "es": "Recibo", "fr": "Reçu", "de": "Quittung", "it": "Ricevuta",
    "pt": "Recibo",
  ],
  [
    "en": "Report", "es": "Informe", "fr": "Rapport", "de": "Bericht", "it": "Rapporto",
    "pt": "Relatório",
  ],
  [
    "en": "Contract", "es": "Contrato", "fr": "Contrat", "de": "Vertrag", "it": "Contratto",
    "pt": "Contrato",
  ],
  ["en": "Letter", "es": "Carta", "fr": "Lettre", "de": "Brief", "it": "Lettera", "pt": "Carta"],
]

func translatedDescriptors(in text: String, language: String) -> [String] {
  let words = Set(text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted))
  return descriptors.compactMap { group in
    guard group.values.contains(where: { words.contains($0.lowercased()) }) else { return nil }
    return group[language]
  }
}

func translatedContentTitle(_ title: String, original: String, language: String) -> String {
  var result = title
  let protected = Set(
    original.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted))
  for group in descriptors {
    guard let target = group[language] else { continue }
    for source in Set(group.values)
    where source != target && !protected.contains(source.lowercased()) {
      let pattern =
        #"(?<![\p{L}\p{M}\p{N}])"# + NSRegularExpression.escapedPattern(for: source)
        + #"(?![\p{L}\p{M}\p{N}])"#
      result = result.replacingOccurrences(
        of: pattern, with: target, options: [.regularExpression, .caseInsensitive])
    }
  }
  return result
}

func descriptorLanguageMatches(_ text: String, original: String, language: String) -> Bool {
  guard language != "und" else { return true }
  let words = Set(text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted))
  let originalWords = Set(
    original.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted))
  return descriptors.allSatisfy { group in
    group.values.allSatisfy { word in
      !words.contains(word.lowercased()) || originalWords.contains(word.lowercased())
        || group[language] == word
    }
  }
}

func requestedNamingLanguage(_ value: String, request: String) -> String? {
  guard !value.isEmpty, request.contains(value) else { return nil }
  let escaped = NSRegularExpression.escapedPattern(for: value.lowercased())
  let instruction = metadataInstructionText(request)
  guard
    instruction.range(
      of: #"(?:\b(?:in|into|to|en|auf|em|en langue|in lingua)\s+"# + escaped
        + #"\b|\b"# + escaped + #"\s+(?:file)?names?\b)"#,
      options: .regularExpression) != nil
  else { return nil }
  for code in ["en", "es", "fr", "de", "it", "pt"] {
    for locale in ["en", "es", "fr", "de", "it", "pt"] {
      if Locale(identifier: locale).localizedString(forLanguageCode: code)?.lowercased()
        == value.lowercased()
      {
        return code
      }
    }
  }
  return nil
}
