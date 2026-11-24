import Foundation

struct TooFewFiles: Error, CustomStringConvertible {
    let folder: URL
    let found: Int
    let minimum: Int
    var description: String { "\(folder.path) holds \(found) Swift files, fewer than the \(minimum) a scan of the sources expects: a wrong path would scan nothing and pass" }
}

/// Every Swift file under `folder`, subfolders included. A scan that finds fewer than `minimum` is looking in the wrong place, so it fails instead of passing on nothing.
func swiftFiles(under folder: URL, minimum: Int) throws -> [URL] {
    let walk = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
    let files = (walk?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "swift" }
    guard files.count >= minimum else { throw TooFewFiles(folder: folder, found: files.count, minimum: minimum) }
    return files
}
