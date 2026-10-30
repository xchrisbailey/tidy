import Foundation

// Keep original proposals reserved so a collision never steals another file's unsuffixed name.
// Callers supply case-folded names and retain their own filesystem and filename-limit validation.
func allocateName(
  _ proposed: String, occupied: Set<String>, reserved: Set<String>, allocated: Set<String>
) -> String {
  guard occupied.contains(proposed.lowercased()) || allocated.contains(proposed.lowercased()) else {
    return proposed
  }
  let url = URL(fileURLWithPath: proposed)
  let ext = url.pathExtension
  let stem = ext.isEmpty ? proposed : url.deletingPathExtension().lastPathComponent
  var suffix = 2
  var name: String
  repeat {
    name = "\(stem) (\(suffix))" + (ext.isEmpty ? "" : ".\(ext)")
    suffix += 1
  } while occupied.contains(name.lowercased()) || reserved.contains(name.lowercased())
    || allocated.contains(name.lowercased())
  return name
}
