import Foundation

/// The letters of a project's icon, always capitals: the first letters of its first three words (`fury-invest-returns` is FIR), or the
/// first two letters of a one-word name (`carrier` is CA). Three letters tell apart projects that share their first two words. A name
/// with a parent folder in front (`dev/carrier`) is the last part.
public func projectInitials(_ name: String) -> String {
    let last = name.split(separator: "/").last.map(String.init) ?? name
    let words = last.split(whereSeparator: { "-_ .".contains($0) })
    guard let first = words.first else { return "?" }
    let letters = words.count > 1 ? words.prefix(3).compactMap { $0.first }.map(String.init).joined() : String(first.prefix(2))
    return letters.uppercased()
}

/// What a project's colour is made from: the last part of its folder or of `owner/name`, in lower case, so the folder of a session and
/// the repository of an epic that are the same project have the same colour.
public func projectColorKey(_ pathOrRepo: String) -> String {
    (pathOrRepo.split(separator: "/").last.map(String.init) ?? pathOrRepo).lowercased()
}

/// Which of `count` colours a project has: the same one in every launch and for every session of it (`hashValue` is not, it changes
/// at each launch). FNV-1a over the project's folder.
public func projectColorIndex(_ folder: String, count: Int) -> Int {
    guard count > 0 else { return 0 }
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in folder.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3 }
    return Int(hash % UInt64(count))
}
