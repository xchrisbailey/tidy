import Foundation

func strictPlanJSON(_ text: String) -> Bool {
  let data = Data(text.utf8)
  guard let object = try? JSONSerialization.jsonObject(with: data),
    let envelope = object as? [String: Any],
    Set(envelope.keys) == ["status", "message", "clauses", "sort", "rename", "selection", "files"],
    let clauses = envelope["clauses"] as? [[String: Any]],
    clauses.allSatisfy({ Set($0.keys) == ["text", "effect"] }),
    let sort = envelope["sort"] as? [String: Any], Set(sort.keys) == ["kind", "evidence", "value"],
    let rename = envelope["rename"] as? [[String: Any]],
    rename.allSatisfy({ Set($0.keys) == ["kind", "evidence", "value", "from"] }),
    let selection = envelope["selection"] as? [String: Any],
    Set(selection.keys) == ["extensions", "nameContains", "evidence"],
    validPlanFiles(envelope["files"])
  else { return false }
  return uniqueJSONKeys(data)
}

private func validPlanFiles(_ value: Any?) -> Bool {
  if value as? String == "all" { return true }
  guard let files = value as? [[String: Any]] else { return false }
  return files.allSatisfy { Set($0.keys) == ["sourceID", "disposition"] }
}

func strictNamingJSON(_ text: String) -> Bool {
  let data = Data(text.utf8)
  guard let envelope = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
    Set(envelope.keys) == ["files"], let files = envelope["files"] as? [[String: Any]],
    files.allSatisfy({
      (Set($0.keys) == ["sourceID", "title", "name", "disposition"] && $0["name"] is String)
        || Set($0.keys) == ["sourceID", "title", "disposition"]
    })
  else { return false }
  return uniqueJSONKeys(data)
}

private func uniqueJSONKeys(_ data: Data) -> Bool {
  // Foundation decoders accept duplicate keys. Reject them before interpreting any model authority.
  let bytes = Array(data)
  var objects: [Set<String>] = []
  var index = 0
  while index < bytes.count {
    switch bytes[index] {
    case 123: objects.append([])
    case 125:
      guard !objects.isEmpty else { return false }
      objects.removeLast()
    case 34:
      let start = index
      index += 1
      while index < bytes.count {
        if bytes[index] == 92 {
          index += 2
          continue
        }
        if bytes[index] == 34 { break }
        index += 1
      }
      guard index < bytes.count else { return false }
      let end = index
      var next = index + 1
      while next < bytes.count && [9, 10, 13, 32].contains(bytes[next]) { next += 1 }
      if next < bytes.count, bytes[next] == 58 {
        guard !objects.isEmpty,
          let key = try? JSONDecoder().decode(String.self, from: Data(bytes[start...end])),
          objects[objects.count - 1].insert(key).inserted
        else { return false }
      }
    default: break
    }
    index += 1
  }
  return objects.isEmpty
}
