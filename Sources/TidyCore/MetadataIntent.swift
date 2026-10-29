import Foundation

enum IntentViolation: String, Error {
  case coverage =
    "Copy every request clause exactly, in order, including spaces and punctuation, using only the documented effects."
  case envelope =
    "Use the complete documented envelope; clarification/unsupported has no rules or files."
  case sources =
    "For a plan use files: \"all\" so the app expands every captured source; do not invent source IDs. message must be empty and an action is required."
  case sort =
    "If sorting or moving was NOT requested, sort.kind MUST be none, with evidence/value empty. Do not copy type from the example into a rename-only task. Otherwise use a documented sort kind with exact request evidence for the sorting action and type, date source/precision, or quoted folder literal."
  case rename =
    "Use only documented rename rules with exact positive user-request evidence and literal parameters. Respect restrictions against renaming."
  case renameEvidence =
    "A rename rule's evidence must be copied from a clause whose effect includes rename. Copy the complete positive action clause verbatim, not a paraphrase or a fragment from another clause. Preserve quoted literals exactly."
  case renameSeparator =
    "A separator rule needs the requested replacement verb and BOTH source/target separators in its evidence. from/value are literal space, underscore or hyphen characters, not words."
  case renameCase =
    "A case rule needs the explicit requested lowercase/uppercase/title-case phrase in its evidence, with value and from both empty."
  case renameLiteral =
    "A prefix/suffix rule needs its action word AND the exact quoted literal in its evidence. Copy the user's literal including case and whitespace; from must be empty."
  case selection =
    "Selection evidence must quote an explicitly requested extension or exact quoted name substring, never a generic word like files. If extensions and nameContains are both empty, evidence MUST also be empty: {\"extensions\":[],\"nameContains\":\"\",\"evidence\":\"\"}, and REMOVE selection from clause effects (use rename, not rename+selection, for content naming without a filter). Do not infer a filter from inventory. A clause declaring a filter must include the selection effect."
  case clauses =
    "Each clause must correspond to an actual declared rule or a preservation constraint; do not hide unsupported actions."
}

struct MetadataIntent: Decodable {
  let status: String
  let message: String
  let clauses: [Clause]
  let sort: SortRule
  let rename: [RenameRule]
  let selection: Selection
  let files: [Decision]
  let appliesToAll: Bool

  enum CodingKeys: String, CodingKey {
    case status, message, clauses, sort, rename, selection, files
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    status = try values.decode(String.self, forKey: .status)
    message = try values.decode(String.self, forKey: .message)
    clauses = try values.decode([Clause].self, forKey: .clauses)
    sort = try values.decode(SortRule.self, forKey: .sort)
    rename = try values.decode([RenameRule].self, forKey: .rename)
    selection = try values.decode(Selection.self, forKey: .selection)
    if let coverage = try? values.decode(String.self, forKey: .files), coverage == "all" {
      appliesToAll = true
      files = []
    } else {
      appliesToAll = false
      files = try values.decode([Decision].self, forKey: .files)
    }
  }

  func applies(to sourceID: String) -> Bool {
    appliesToAll || files.contains { $0.sourceID == sourceID && $0.disposition == "apply" }
  }

  struct Clause: Codable {
    let text: String
    let effect: String
    var effects: [String] { effect.split(separator: "+").map(String.init) }
    func supports(_ effect: String) -> Bool { effects.contains(effect) }
    var validEffect: Bool {
      if ["constraint", "unsupported", "ambiguous"].contains(effect) { return true }
      return !effects.isEmpty && effects.count <= 3 && Set(effects).count == effects.count
        && effects.allSatisfy { ["sort", "rename", "selection"].contains($0) }
    }
  }
  struct SortRule: Codable {
    let kind: String
    let evidence: String
    let value: String
  }
  struct RenameRule: Codable {
    let kind: String
    let evidence: String
    let value: String
    let from: String
  }
  struct Selection: Codable {
    let extensions: [String]
    let nameContains: String
    let evidence: String
  }
  struct Decision: Codable {
    let sourceID: String
    let disposition: String
  }

  // Evidence is checked against the request, not the untrusted metadata or the model's explanation.
  // Interpretation may choose bounded rules; it cannot supply arbitrary operations or filesystem paths.
  func validate(request: String, sourceIDs: Set<String>) throws {
    guard clauses.count <= 32, requestWords(clauses.map(\.text).joined()) == requestWords(request),
      clauses.allSatisfy({
        !$0.text.isEmpty && $0.validEffect
      }),
      rename.count <= 4, message.utf8.count <= 1_024
    else { throw IntentViolation.coverage }
    if status != "plan" {
      guard ["unsupported", "clarification"].contains(status), !message.isEmpty, files.isEmpty,
        !appliesToAll,
        sort.kind == "none", sort.evidence.isEmpty, sort.value.isEmpty, rename.isEmpty,
        selection.extensions.isEmpty, selection.nameContains.isEmpty, selection.evidence.isEmpty
      else { throw IntentViolation.envelope }
      return
    }
    guard message.isEmpty,
      !clauses.contains(where: { ["unsupported", "ambiguous"].contains($0.effect) }),
      appliesToAll || (files.count == sourceIDs.count && Set(files.map(\.sourceID)) == sourceIDs),
      files.allSatisfy({ ["apply", "abstain"].contains($0.disposition) }),
      sort.kind != "none" || !rename.isEmpty
    else { throw IntentViolation.sources }
    func evidence(_ text: String, effect: String) -> Bool {
      !text.isEmpty
        && clauses.contains { clause in
          guard clause.supports(effect), containsEvidence(text, in: clause.text) else {
            return false
          }
          let negated =
            #"\b(?:not|never|don't|without|avoid|no)\s+(?:\w+\s+){0,2}"#
            + NSRegularExpression.escapedPattern(for: canonicalProse(text))
          return canonicalProse(clause.text).range(of: negated, options: .regularExpression) == nil
        }
    }
    if sort.kind != "none" {
      guard
        clauses.contains(where: { clause in
          clause.supports("sort") && containsEvidence(sort.evidence, in: clause.text)
            && hasSortingAction(clause.text)
        }),
        ![
          "do not sort", "don't sort", "do not move", "don't move", "rename only", "only rename",
          "without moving",
        ].contains(where: metadataInstructionText(request).contains)
      else { throw IntentViolation.sort }
    }
    let sortWords = metadataInstructionText(sort.evidence)
    let year = containsWord(sortWords, ["year", "years", "yyyy"])
    let month = containsWord(sortWords, ["month", "months", "monthly", "yyyy-mm"])
    let filename = sortWords.contains("name")
    let modified = sortWords.contains("modif") || sortWords.contains("last changed")
    switch sort.kind {
    case "none":
      guard sort.evidence.isEmpty, sort.value.isEmpty else { throw IntentViolation.sort }
    case "type":
      guard evidence(sort.evidence, effect: "sort"), sort.value.isEmpty,
        containsWord(
          sortWords,
          ["type", "types", "kind", "kinds", "extension", "extensions", "format", "formats"])
      else { throw IntentViolation.sort }
    case "filenameYear", "filenameMonth", "modifiedYear", "modifiedMonth":
      guard evidence(sort.evidence, effect: "sort"), sort.value.isEmpty,
        sort.kind.hasPrefix("filename") ? filename && !modified : modified,
        sort.kind.hasSuffix("Year") ? year : month
      else { throw IntentViolation.sort }
    case "folder":
      guard evidence(sort.evidence, effect: "sort"), validDestinationFolder(sort.value),
        sort.value != ".",
        quotedLiteral(sort.value, in: sort.evidence), quotedLiteral(sort.value, in: request)
      else { throw IntentViolation.sort }
    default: throw IntentViolation.sort
    }
    let lower = metadataInstructionText(request)
    if !rename.isEmpty {
      guard
        ![
          "do not rename", "don't rename", "without renaming", "keep original names",
          "keep the original names", "leave names unchanged", "preserve filenames",
        ].contains(where: lower.contains)
      else { throw IntentViolation.rename }
    }
    for rule in rename {
      guard evidence(rule.evidence, effect: "rename") else { throw IntentViolation.renameEvidence }
      let words = metadataInstructionText(rule.evidence)
      switch rule.kind {
      case "content":
        guard rename.count == 1, rule.from.isEmpty,
          authorizesContentNaming(rule.evidence),
          rule.value.isEmpty || requestedNamingLanguage(rule.value, request: request) != nil
        else {
          throw IntentViolation.rename
        }
      case "separator":
        guard [" ", "_", "-"].contains(rule.from), [" ", "_", "-"].contains(rule.value),
          rule.from != rule.value,
          containsWord(
            words,
            [
              "replace", "replacing", "change", "changing", "use", "using", "swap", "separators",
              "separator", "normalize", "substitute",
            ]),
          separatorMention(rule.from, in: rule.evidence.lowercased()),
          separatorMention(rule.value, in: rule.evidence.lowercased())
        else { throw IntentViolation.renameSeparator }
      case "lowercase", "uppercase", "titlecase":
        let terms =
          rule.kind == "lowercase"
          ? ["lowercase", "lower case", "lower-case"]
          : rule.kind == "uppercase"
            ? ["uppercase", "upper case", "upper-case", "all caps"]
            : ["title case", "titlecase", "title-case", "capitalize"]
        guard rule.value.isEmpty, rule.from.isEmpty, terms.contains(where: words.contains) else {
          throw IntentViolation.renameCase
        }
      case "prefix", "suffix":
        guard rule.from.isEmpty, !rule.value.isEmpty, rule.value.utf8.count <= 80,
          validNameFragment(rule.value), quotedLiteral(rule.value, in: rule.evidence),
          quotedLiteral(rule.value, in: request),
          (rule.kind == "prefix"
            ? ["prefix", "prepend", "start", "begin"] : ["suffix", "append", "end"]).contains(
              where: words.contains)
        else { throw IntentViolation.renameLiteral }
      case "filenameDatePrefix", "modifiedDatePrefix":
        guard rule.value.isEmpty, rule.from.isEmpty, words.contains("date"),
          ["prefix", "prepend", "start", "begin"].contains(where: words.contains),
          rule.kind == "filenameDatePrefix" ? words.contains("name") : words.contains("modif")
        else { throw IntentViolation.rename }
      default: throw IntentViolation.rename
      }
      guard
        !containsWord(metadataInstructionText(rule.evidence), ["not", "never", "don't", "without"])
      else {
        throw IntentViolation.rename
      }
    }
    guard selection.extensions.count <= 16,
      Set(selection.extensions).count == selection.extensions.count
    else { throw IntentViolation.selection }
    if !selection.extensions.isEmpty || !selection.nameContains.isEmpty {
      guard evidence(selection.evidence, effect: "selection"),
        selection.extensions.allSatisfy({ ext in
          !ext.isEmpty && ext.utf8.count <= 10
            && ext.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
            && containsWord(
              selection.evidence.lowercased(), [ext.lowercased(), ext.lowercased() + "s"])
        }),
        selection.nameContains.isEmpty
          || (quotedLiteral(selection.nameContains, in: selection.evidence)
            && quotedLiteral(selection.nameContains, in: request))
      else { throw IntentViolation.selection }
    } else if !selection.evidence.isEmpty {
      throw IntentViolation.selection
    }
    guard
      clauses.allSatisfy({ clause in
        if clause.effect == "constraint" {
          return containsWord(
            clause.text.lowercased(),
            [
              "preserve", "keep", "retain", "unchanged", "only", "please", "thanks", "not", "never",
              "don't", "without", "no",
            ])
        }
        return clause.effects.allSatisfy { effect in
          switch effect {
          case "sort":
            return sort.kind != "none" && containsEvidence(sort.evidence, in: clause.text)
          case "rename": return rename.contains { containsEvidence($0.evidence, in: clause.text) }
          case "selection":
            return !selection.evidence.isEmpty
              && containsEvidence(selection.evidence, in: clause.text)
          default: return false
          }
        }
      })
    else { throw IntentViolation.clauses }
  }
}

private func hasSortingAction(_ text: String) -> Bool {
  let instruction = metadataInstructionText(text)
  // A noun such as "file names" or a quoted label is not permission to move files.
  let verbs =
    #"\b(?:sort(?:ed|ing)?|mov(?:e[ds]?|ing)|put(?:ting)?|organi[sz](?:e[ds]?|ing)|group(?:ed|ing)?|arrang(?:e[ds]?|ing)|bucket(?:ed|ing)?|collect(?:ed|ing)?|separat(?:e[ds]?|ing)|stor(?:e[ds]?|ing)|categori[sz](?:e[ds]?|ing)|classif(?:y|ied|ying)|plac(?:e[ds]?|ing)|relocat(?:e[ds]?|ing))\b"#
  return instruction.range(of: verbs, options: .regularExpression) != nil
    || instruction.range(
      of: #"\bfil(?:e|ed|ing)\s+(?:these|the|my|our|all|selected)\b"#, options: .regularExpression)
      != nil
}

func metadataInstructionText(_ text: String) -> String {
  canonicalProse(text).replacingOccurrences(
    of: #"\"[^\"]*\"|(?<![\p{L}\p{N}])'[^']*'(?![\p{L}\p{N}])"#, with: "",
    options: .regularExpression)
}

private func requestWords(_ text: String) -> [String] {
  // Presentation punctuation is not authority. Literal rule values are separately checked against
  // exact quoted user text, so this cannot normalize a path, prefix or suffix into authorization.
  canonicalProse(text).components(separatedBy: CharacterSet.alphanumerics.inverted).filter {
    !$0.isEmpty
  }
}

private func canonicalProse(_ text: String) -> String {
  text.replacingOccurrences(of: "‘", with: "'").replacingOccurrences(of: "’", with: "'")
    .replacingOccurrences(of: "“", with: "\"").replacingOccurrences(of: "”", with: "\"")
    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    .trimmingCharacters(in: .whitespacesAndNewlines).lowercased(
      with: Locale(identifier: "en_US_POSIX"))
}

private func containsEvidence(_ evidence: String, in text: String) -> Bool {
  canonicalProse(text).contains(canonicalProse(evidence))
}

func containsWord(_ text: String, _ words: [String]) -> Bool {
  words.contains { word in
    text.range(
      of: "(?<![a-z0-9])" + NSRegularExpression.escapedPattern(for: word) + "(?![a-z0-9])",
      options: .regularExpression) != nil
  }
}

private func quotedLiteral(_ value: String, in text: String) -> Bool {
  ["\"\(value)\"", "‘\(value)’", "'\(value)'", "“\(value)”"].contains(where: text.contains)
}

private func separatorMention(_ value: String, in text: String) -> Bool {
  switch value {
  case " ": containsWord(text, ["space", "spaces", "whitespace"]) || quotedLiteral(value, in: text)
  case "_": containsWord(text, ["underscore", "underscores"]) || quotedLiteral(value, in: text)
  case "-":
    containsWord(text, ["hyphen", "hyphens", "dash", "dashes"]) || quotedLiteral(value, in: text)
  default: false
  }
}

func validNameFragment(_ value: String) -> Bool {
  !value.contains("/") && !value.contains("\\") && !value.contains(":")
    && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
}

func validDestinationFolder(_ value: String) -> Bool {
  value == "." || (validFileName(value) && !value.hasPrefix(".") && validNameFragment(value))
}
