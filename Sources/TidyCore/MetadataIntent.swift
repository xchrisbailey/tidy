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
    "A separator rule must bind the requested direction: replace/change SOURCE with/to TARGET, substitute TARGET for SOURCE, or use TARGET instead of SOURCE. from/value are literal space, underscore or hyphen characters, not words. Do not reverse or guess an ambiguous direction."
  case namingLanguage =
    "A content naming rule must copy the explicitly requested output language into value; never omit it or substitute another language. If multiple output languages are requested, ask for clarification."
  case renameCase =
    "A case rule needs the explicit requested lowercase/uppercase/title-case phrase in its evidence, with value and from both empty."
  case renameLiteral =
    "A prefix/suffix rule needs its action word AND the exact quoted literal in its evidence. Copy the user's literal including case and whitespace; from must be empty."
  case selection =
    "Bind selection to positive action scope, not mentions inside preservation constraints. Never narrow an all-files action. One global selection must match every requested action; ask for clarification if action scopes differ. Preserve every explicit extension and quoted name-substring restriction; never omit or broaden one. Exact-file selection is not supported: ask for clarification instead of using a substring filter. Selection evidence must quote an explicitly requested extension or exact quoted name substring, never a generic word like files. If extensions and nameContains are both empty, evidence MUST also be empty: {\"extensions\":[],\"nameContains\":\"\",\"evidence\":\"\"}, and REMOVE selection from clause effects (use rename, not rename+selection, for content naming without a filter). Do not infer a filter from inventory. A clause declaring a filter must include the selection effect."
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
        let requestedLanguages = explicitNamingLanguages(in: request)
        guard
          requestedLanguages.isEmpty
            ? rule.value.isEmpty
            : requestedLanguages
              == Set([requestedNamingLanguage(rule.value, request: request)].compactMap { $0 })
        else { throw IntentViolation.namingLanguage }
      case "separator":
        guard [" ", "_", "-"].contains(rule.from), [" ", "_", "-"].contains(rule.value),
          rule.from != rule.value,
          requestedSeparatorChange(from: rule.from, to: rule.value, in: rule.evidence)
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
    // Optional model fields cannot erase a recognizable restriction in the user's request.
    // Check authority before expansion or content inspection treats an empty filter as all files.
    let parts = try requestClauses(request)
    let actionClauses = parts.actions
    let selectionRequest = actionClauses.joined(separator: " ")
    var boundScope: SelectionRestrictions?
    for clause in actionClauses {
      let parsed = try selectionRestrictions(in: clause)
      let words = metadataInstructionText(clause)
      // Unrecognized preservation phrasing is not a positive selector either. Ask for
      // clarification rather than using an extension mention to narrow a generic action.
      if !parsed.isEmpty
        && containsWord(
          words, ["unchanged", "keep", "keeping", "preserve", "preserving", "retain", "retaining"])
      {
        throw IntentViolation.selection
      }
      let allFiles =
        words.range(
          of: #"\b(?:all|every|each)\s+(?:the\s+)?(?:files?|filenames?|names?|documents?)\b"#,
          options: .regularExpression) != nil
      guard !(allFiles && !parsed.isEmpty),
        parsed.isEmpty
          || !containsWord(words, ["except", "excluding", "exclude", "without", "not", "never"])
      else { throw IntentViolation.selection }
      let explicitScope =
        !parsed.isEmpty || allFiles || containsWord(words, ["files", "documents"])
      let scope = explicitScope ? parsed : boundScope ?? parsed
      if let boundScope, scope != boundScope { throw IntentViolation.selection }
      boundScope = scope
    }
    let requested = boundScope ?? SelectionRestrictions()
    let nameRestrictions = requested.names
    guard Set(selection.extensions.map { $0.lowercased() }) == requested.extensions,
      nameRestrictions == (selection.nameContains.isEmpty ? [] : [selection.nameContains])
    else { throw IntentViolation.selection }
    try validatePreservationConstraints(
      parts.constraints, hasSort: sort.kind != "none", hasRename: !rename.isEmpty,
      selectedExtensions: requested.extensions)
    // Exact-file selection is not representable by the substring filter. Require clarification
    // instead of treating a quoted file name as authority over its neighbours.
    if selectionRequest.range(
      of: #"(?i)\b(?:file|files?\s+(?:named|called))\s+[\"“‘'][^\"”’']+[\"”’']"#,
      options: .regularExpression) != nil
    {
      throw IntentViolation.selection
    }
    let quotedFile = try NSRegularExpression(
      pattern: #"[\"“‘']([^\"”’']+\.[a-zA-Z0-9]{1,10})[\"”’']"#)
    for match in quotedFile.matches(
      in: selectionRequest, range: NSRange(selectionRequest.startIndex..., in: selectionRequest))
    {
      guard let range = Range(match.range(at: 1), in: selectionRequest) else { continue }
      let literal = String(selectionRequest[range])
      let isRuleParameter =
        rename.contains {
          ["prefix", "suffix"].contains($0.kind) && $0.value == literal
        } || (sort.kind == "folder" && sort.value == literal)
      guard isRuleParameter || nameRestrictions.contains(literal) else {
        throw IntentViolation.selection
      }
    }
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

private struct SelectionRestrictions: Equatable {
  var extensions: Set<String> = []
  var names: Set<String> = []
  var isEmpty: Bool { extensions.isEmpty && names.isEmpty }
}

private func selectionRestrictions(in clause: String) throws -> SelectionRestrictions {
  let instruction = metadataInstructionText(clause)
  let knownExtensions = [
    "pdf", "txt", "md", "markdown", "rtf", "doc", "docx", "csv", "tsv", "xls", "xlsx",
    "ppt", "pptx", "jpg", "jpeg", "png", "gif", "heic", "tiff", "svg", "webp",
    "mp3", "wav", "m4a", "mp4", "mov", "zip", "json", "xml", "html",
  ]
  var result = SelectionRestrictions(
    extensions: Set(
      knownExtensions.filter {
        containsWord(instruction, [$0, $0 + "s"])
      }))
  let dotted = try NSRegularExpression(pattern: #"(?<![a-z0-9])\.([a-z0-9]{1,10})\b"#)
  for match in dotted.matches(
    in: instruction, range: NSRange(instruction.startIndex..., in: instruction))
  {
    if let range = Range(match.range(at: 1), in: instruction) {
      result.extensions.insert(String(instruction[range]))
    }
  }
  let quotedExtension = try NSRegularExpression(
    pattern: #"(?i)[\"“‘']\.([a-z0-9]{1,10})[\"”’']\s+(?:files?|documents?)\b"#)
  for match in quotedExtension.matches(in: clause, range: NSRange(clause.startIndex..., in: clause))
  {
    if let range = Range(match.range(at: 1), in: clause) {
      result.extensions.insert(clause[range].lowercased())
    }
  }
  let nameFilter = try NSRegularExpression(
    pattern:
      #"(?i)\b(?:names?|filenames?|files?)\s+(?:that\s+)?(?:contain(?:s|ing)?|include(?:s|ing)?|matching)\s+[\"“‘']([^\"”’']+)[\"”’']"#
  )
  for match in nameFilter.matches(in: clause, range: NSRange(clause.startIndex..., in: clause)) {
    if let range = Range(match.range(at: 1), in: clause) {
      result.names.insert(String(clause[range]))
    }
  }
  return result
}

func requestClauses(_ request: String) throws -> (
  actions: [String], constraints: [String]
) {
  // Split the request independently of the model's clause/effect declarations. Quoted literals
  // are consumed first so action words inside a name or prefix cannot introduce another scope.
  let preservation =
    #"keep(?:ing)?|preserv\w*|retain(?:ing)?|leav(?:e|ing)|never|without|don't|do\s+not"#
  let sorting =
    #"sort\w*|mov(?:e|ing)|put\w*|organi[sz]\w*|group\w*|arrang\w*|bucket\w*|collect\w*|separat\w*|stor\w*|categori[sz]\w*|classif\w*|plac\w*|relocat\w*"#
  let naming =
    #"renam\w*|translat\w*|giv(?:e|ing)|lower[ -]?case|upper[ -]?case|title[ -]?case|all\s+caps|capitaliz\w*|replac\w*|chang\w*|us(?:e|ing)|swap\w*|normaliz\w*|substitut\w*|prepend\w*|append\w*|prefix|suffix|start\w*|begin\w*"#
  let boundaries = try NSRegularExpression(
    pattern:
      #"[\"“][^\"”]*[\"”]|‘[^’]*’|(?<!\w)'[^']*'(?!\w)|(?:\s+(?:and|but|then|while)\s+|[,;.!?]\s*|\s+(?=(?:preserving|keeping|retaining|leaving)\b))(?=(?:please\s+)?(?:"#
      + preservation + "|" + sorting + "|" + naming + #")\b)"#,
    options: .caseInsensitive)
  var clauses: [String] = []
  var start = request.startIndex
  for match in boundaries.matches(in: request, range: NSRange(request.startIndex..., in: request)) {
    guard let range = Range(match.range, in: request),
      !["\"", "“", "‘", "'"].contains(String(request[range].prefix(1)))
    else { continue }
    clauses.append(String(request[start..<range.lowerBound]))
    start = range.upperBound
  }
  clauses.append(String(request[start...]))
  var actions: [String] = []
  var constraints: [String] = []
  for clause in clauses {
    let words = metadataInstructionText(clause).trimmingCharacters(in: .whitespacesAndNewlines)
    let constraint =
      words.range(
        of: #"^(?:please\s+)?(?:"# + preservation + #")\b"#,
        options: .regularExpression) != nil
    if constraint { constraints.append(clause) } else { actions.append(clause) }
  }
  return (actions, constraints)
}

private func validatePreservationConstraints(
  _ clauses: [String], hasSort: Bool, hasRename: Bool, selectedExtensions: Set<String>
) throws {
  for clause in clauses {
    let words = metadataInstructionText(clause).trimmingCharacters(in: .whitespacesAndNewlines)
    let protectedExtensions = try selectionRestrictions(in: clause).extensions
    let disjoint =
      !selectedExtensions.isEmpty && !protectedExtensions.isEmpty
      && selectedExtensions.isDisjoint(with: protectedExtensions)
    let names = containsWord(words, ["name", "names", "filename", "filenames"])
    let contents = containsWord(words, ["content", "contents", "bytes"])
    let unchanged = containsWord(
      words, ["unchanged", "original", "preserve", "preserving", "retain"])
    // A global filter cannot encode action-specific exceptions. Only redundant preservation
    // of data/names is harmless here; never turn a negative/preservation clause into a filter.
    if !disjoint
      && ((names && hasRename)
        || (hasSort && containsWord(words, ["folder", "folders", "location", "untouched"])))
    {
      throw IntentViolation.selection
    }
    if names || contents {
      guard unchanged else { throw IntentViolation.selection }
    } else if !protectedExtensions.isEmpty && !disjoint {
      let forbidsRenaming =
        words.range(
          of: #"^(?:never|don't|do\s+not)\s+rename\b"#, options: .regularExpression) != nil
      guard !hasRename && forbidsRenaming else { throw IntentViolation.selection }
    }
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

private func requestedSeparatorChange(from: String, to: String, in evidence: String) -> Bool {
  func operand(_ value: String) -> String {
    let word: String
    switch value {
    case " ": word = #"\b(?:spaces?|whitespace)\b"#
    case "_": word = #"\bunderscores?\b"#
    default: word = #"\b(?:hyphens?|dashes)\b"#
    }
    let literal = NSRegularExpression.escapedPattern(for: value)
    return "(?:" + word + #"|[\"“‘']"# + literal + #"[\"”’'])"#
  }
  let source = operand(from)
  let target = operand(to)
  guard
    let quoted = try? NSRegularExpression(
      pattern: #"[\"“][^\"”]*[\"”]|‘[^’]*’|(?<!\w)'[^']*'(?!\w)"#)
  else { return false }
  var instruction = evidence
  for match in quoted.matches(in: evidence, range: NSRange(evidence.startIndex..., in: evidence))
    .reversed()
  {
    guard let range = Range(match.range, in: instruction) else { continue }
    let text = String(instruction[range])
    if ![" ", "_", "-"].contains(String(text.dropFirst().dropLast())) {
      instruction.replaceSubrange(range, with: " ")
    }
  }
  // Mere mentions of both separators do not authorize their direction. Ambiguous
  // phrasing stays invalid rather than letting model parameters choose the operation.
  let patterns = [
    #"\b(?:replace|replacing|change|changing)\s+"#
      + source + #"\s+(?:with|to|into)\s+"# + target,
    #"\b(?:swap|swapping)\s+"# + source + #"\s+(?:with|for)\s+"# + target,
    #"\b(?:substitute|substituting)\s+"# + source + #"\s+with\s+"# + target,
    #"\b(?:change|changing|normalize|normalizing)\s+(?:separators?\s+)?from\s+"#
      + source + #"\s+to\s+"# + target,
    #"\b(?:substitute|substituting)\s+"# + target + #"\s+for\s+"# + source,
    #"\b(?:use|using)\s+"# + target + #"\s+(?:instead\s+of|in\s+place\s+of|rather\s+than)\s+"#
      + source,
  ]
  return patterns.contains {
    instruction.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil
  }
}

func validNameFragment(_ value: String) -> Bool {
  !value.contains("/") && !value.contains("\\") && !value.contains(":")
    && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
}

func validDestinationFolder(_ value: String) -> Bool {
  value == "." || (validFileName(value) && !value.hasPrefix(".") && validNameFragment(value))
}
