import Darwin
import Foundation

func relativeParent(_ path: String) -> String {
  let parts = path.split(separator: "/")
  return parts.count > 1 ? parts.dropLast().joined(separator: "/") : "."
}

func relativeLeaf(_ path: String) -> String {
  String(path.split(separator: "/").last ?? "")
}

func validRelativePath(_ path: String) -> Bool {
  !path.isEmpty && path.utf8.count < Int(PATH_MAX)
    && path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
      validFileName(String($0)) && !$0.hasPrefix(".")
    }
}

func validSourceAuthority(_ path: String, _ identities: [String: FileIdentity]?) -> Bool {
  guard validRelativePath(path) else { return false }
  let components = path.split(separator: "/").dropLast()
  for index in components.indices {
    guard identities?[components.prefix(index + 1).joined(separator: "/")] != nil else {
      return false
    }
  }
  return (identities ?? [:]).keys.allSatisfy(validRelativePath)
}

// Each component is opened separately: O_NOFOLLOW on a slash-containing path protects only its leaf.
func relativeDirectory(_ root: Int32, _ path: String) throws -> Int32 {
  guard path == "." || validRelativePath(path) else { throw SortError.invalidPlan }
  var current = dup(root)
  guard current >= 0 else { throw SortError.unavailable }
  do {
    if path != "." {
      for component in path.split(separator: "/") {
        guard let before = entryInfo(current, String(component)),
          before.st_mode & S_IFMT == S_IFDIR,
          before.st_flags & UInt32(SF_DATALESS | UF_HIDDEN) == 0
        else { throw SortError.uncertainIdentity }
        let next = openat(
          current, String(component), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard next >= 0 else { throw SortError.uncertainIdentity }
        var info = stat()
        guard fstat(next, &info) == 0, FileIdentity(info) == FileIdentity(before),
          info.st_flags & UInt32(SF_DATALESS | UF_HIDDEN) == 0
        else {
          close(next)
          throw SortError.uncertainIdentity
        }
        close(current)
        current = next
      }
    }
    return current
  } catch {
    close(current)
    throw error
  }
}

func validateAncestors(_ root: Int32, _ identities: [String: FileIdentity]?) throws {
  for (path, identity) in identities ?? [:] {
    let directory = try relativeDirectory(root, path)
    defer { close(directory) }
    var info = stat()
    guard fstat(directory, &info) == 0, FileIdentity(info) == identity else {
      throw SortError.uncertainIdentity
    }
  }
}

enum RequestedScope { case direct, recursive, ambiguous }

func requestedScope(_ request: String) -> RequestedScope {
  let text = metadataInstructionText(request)
  let mentions =
    text.range(
      of:
        #"\b(?:subfolders?|subdirector(?:y|ies)|recurs\w*|nested (?:folders?|directories)|descendants?|beneath|below|folder tree)\b"#,
      options: .regularExpression) != nil
  guard mentions else { return .direct }
  if text.contains("?")
    || text.range(
      of: #"\b(?:only|just)\s+(?:the\s+)?(?:direct|immediate|top.level)\b"#,
      options: .regularExpression) != nil
  {
    return .ambiguous
  }
  let negative =
    #"\b(?:not|don't|never|without|exclude|excluding|ignore|ignoring)\s+(?:(?:include|including|traverse|traversing|process|processing|sort|sorting|organize|organizing)\s+)?(?:files\s+(?:in|from)\s+)?(?:the\s+|any\s+|all\s+)?(?:subfolders?|subdirector(?:y|ies)|recurs\w*|descendants?|nested (?:folders?|directories))\b"#
  let positive =
    #"\b(?:recursively|recursive|recurse|(?:include|including|inside|within|throughout|across|in|from)\s+(?:files\s+(?:in|from)\s+)?(?:all\s+|the\s+|any\s+)?(?:subfolders?|subdirectories|descendants?|nested (?:folders?|directories)))\b"#
  let remaining = text.replacingOccurrences(of: negative, with: "", options: .regularExpression)
  if remaining != text {
    return remaining.range(of: positive, options: .regularExpression) == nil ? .direct : .ambiguous
  }
  if containsWord(text, ["subfolder", "subdirectory", "except", "excluding"]) { return .ambiguous }
  if text.range(of: positive, options: .regularExpression) != nil {
    return .recursive
  }
  return .ambiguous
}

extension TaskCoordinator {
  func recursiveInventory(_ root: ScopedDirectory) throws -> FolderInventory {
    var items: [InventoryItem] = []
    var eligibleCount = 0
    var visitedCount = 0
    func walk(_ directory: Int32, path: String, ancestors: [String: FileIdentity], depth: Int)
      throws
    {
      guard depth <= 128 else { throw SortError.scopeTooLarge }
      for name in try exactDirectoryNames(directory, limit: 20_000 - visitedCount).sorted() {
        try Task.checkCancellation()
        visitedCount += 1
        guard visitedCount <= 20_000 else { throw SortError.scopeTooLarge }
        let relative = path.isEmpty ? name : path + "/" + name
        guard relative.utf8.count < Int(PATH_MAX) else { throw SortError.scopeTooLarge }
        guard let info = entryInfo(directory, name) else { throw SortError.staleSource }
        // POSIX eligibility and snapshots come from the pinned parent. Foundation's resource-only
        // package/provider metadata has no fd API; it never authorizes opening or reading contents.
        var item = inspect(root.url.appendingPathComponent(relative), capturedInfo: info)
        try validateAncestors(root.fd, ancestors)
        guard entryInfo(directory, name).map(FileSnapshot.init) == FileSnapshot(info) else {
          throw SortError.staleSource
        }
        item = InventoryItem(
          name: relative, skipReason: item.skipReason, byteCount: item.byteCount,
          modificationDate: item.modificationDate, snapshot: item.snapshot,
          ancestorIdentities: ancestors)
        if item.skipReason == .folder {
          let child = try childDirectory(directory, name)
          defer { close(child) }
          var pinned = stat()
          guard fstat(child, &pinned) == 0, FileIdentity(pinned) == FileIdentity(info) else {
            throw SortError.staleSource
          }
          var next = ancestors
          next[relative] = FileIdentity(info)
          try walk(child, path: relative, ancestors: next, depth: depth + 1)
        } else {
          items.append(item)
          if item.skipReason == nil { eligibleCount += 1 }
          guard eligibleCount <= 1_000 else { throw SortError.scopeTooLarge }
        }
      }
    }
    try walk(root.fd, path: "", ancestors: [:], depth: 0)
    return FolderInventory(folder: root.url, items: items.sorted { $0.name < $1.name })
  }
}

func exactDirectoryNames(_ directory: Int32, limit: Int) throws -> Set<String> {
  let copy = openat(directory, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
  guard copy >= 0 else { throw SortError.unavailable }
  guard let stream = fdopendir(copy) else {
    close(copy)
    throw SortError.unavailable
  }
  defer { closedir(stream) }
  var names: Set<String> = []
  while true {
    try Task.checkCancellation()
    errno = 0
    guard let entry = readdir(stream) else {
      guard errno == 0 else { throw SortError.unavailable }
      return names
    }
    let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
      pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) {
        String(cString: $0)
      }
    }
    if name != "." && name != ".." { names.insert(name) }
    guard names.count <= limit else { throw SortError.scopeTooLarge }
  }
}
