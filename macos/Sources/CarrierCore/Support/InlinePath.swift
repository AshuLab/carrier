import Foundation

/// What a piece of inline code in a message names, when it names a place in a repository: a file (with its extension, lowercased, so a
/// library of icons can be chosen by it) or a folder. Nothing is read from the disk; the text has to look like a path.
public enum InlinePath: Equatable {
    case file(extension: String?)
    case folder
}

/// Extensions that make a bare name a file (`README.md`); anything else needs a `/` to be taken for a path, so `v1.2`, `e.g.` or `foo.bar` stay code.
private let knownExtensions: Set<String> = [
    "md", "txt", "json", "yml", "yaml", "toml", "lock", "plist", "swift", "ts", "tsx", "js", "jsx", "mjs", "py", "rb", "go", "rs", "kt", "java",
    "c", "h", "m", "sh", "zsh", "html", "css", "sql", "xml", "csv", "log", "env", "png", "jpg", "svg", "pdf",
]

/// The allowlist of what a path is made of: no spaces, brackets, quotes or `:`, which also leaves out addresses, calls and commands.
private let pathCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-/~@+")

public func inlinePath(_ code: String) -> InlinePath? {
    guard code.isEmpty == false, code.unicodeScalars.allSatisfy(pathCharacters.contains) else { return nil }
    if code.hasSuffix("/") { return code.count > 1 ? .folder : nil }
    let name = code.split(separator: "/").last.map(String.init) ?? code
    guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return code.contains("/") ? .file(extension: nil) : nil }
    let ext = String(name[name.index(after: dot)...]).lowercased()
    guard ext.isEmpty == false else { return nil }
    if knownExtensions.contains(ext) { return .file(extension: ext) }
    return code.contains("/") && ext.contains(where: \.isLetter) ? .file(extension: ext) : nil
}
