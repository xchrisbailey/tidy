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

private let namingLanguageAliases: [String: String] = {
  var aliases: [String: String] = [:]
  // Recognize other named languages too: limited descriptor support must not silently
  // turn an unsupported requested language into permission to use the source language.
  for code in Locale.LanguageCode.isoLanguageCodes {
    for locale in ["en", "es", "fr", "de", "it", "pt"] {
      if let name = Locale(identifier: locale).localizedString(forLanguageCode: code.identifier) {
        aliases[name.lowercased()] = code.identifier
      }
    }
  }
  return aliases
}()

func explicitNamingLanguages(in request: String) -> Set<String> {
  let lower = request.lowercased()
  var languages = Set(
    namingLanguageAliases.compactMap { name, code in
      namingLanguageMention(name, request: lower) ? code : nil
    })
  let instruction = metadataInstructionText(request)
  // An output-language introducer also governs a coordinated list, not only its
  // first language. A model cannot silently select one member of that list.
  let lists = instruction.matches(of: /\b(?:in|into|to|en|auf|em|en langue|in lingua)\s+([^.;!?]+)/)
  for list in lists {
    let parts = String(list.output.1).replacingOccurrences(
      of: #"\s+(?:and|or)\s+|,\s*"#, with: "\n", options: .regularExpression
    ).components(separatedBy: "\n")
    for part in parts {
      let text = part.trimmingCharacters(in: .whitespaces)
      let language = namingLanguageAliases.filter { name, _ in
        text == name || text.hasPrefix(name + " ")
      }.max { $0.key.count < $1.key.count }
      if let language { languages.insert(language.value) }
    }
  }
  return languages
}

func requestedNamingLanguage(_ value: String, request: String) -> String? {
  guard !value.isEmpty, request.contains(value),
    namingLanguageMention(value.lowercased(), request: request.lowercased()),
    let code = namingLanguageAliases[value.lowercased()],
    ["en", "es", "fr", "de", "it", "pt"].contains(code)
  else { return nil }
  return code
}

private func namingLanguageMention(_ value: String, request: String) -> Bool {
  guard request.contains(value) else { return false }
  let escaped = NSRegularExpression.escapedPattern(for: value)
  let instruction = metadataInstructionText(request)
  return instruction.range(
    of: #"(?:\b(?:in|into|to|en|auf|em|en langue|in lingua)\s+"# + escaped
      + #"\b|\b"# + escaped + #"\s+(?:file\s*)?names?\b)"#,
    options: .regularExpression) != nil
}
