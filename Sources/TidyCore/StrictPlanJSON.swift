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
    let files = envelope["files"] as? [[String: Any]],
    files.allSatisfy({ Set($0.keys) == ["sourceID", "disposition"] })
  else { return false }
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
