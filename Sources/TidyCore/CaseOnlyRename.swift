import Darwin
import Foundation

func isCaseOnlyRename(original: String, folder: String, name: String) -> Bool {
  folder == relativeParent(original) && name != relativeLeaf(original)
    && name.lowercased() == relativeLeaf(original).lowercased()
}

// On a case-insensitive volume the destination can resolve to the pinned source itself.
// RENAME_EXCL still performs the atomic rename and refuses any different occupant at mutation time.
func destinationAvailable(
  _ directory: Int32, _ name: String, caseAliasIdentity: FileIdentity? = nil
) throws -> Bool {
  guard let info = try checkedEntryInfo(directory, name) else { return true }
  return caseAliasIdentity == FileIdentity(info) && info.st_mode & S_IFMT == S_IFREG
    && info.st_nlink == 1
}
