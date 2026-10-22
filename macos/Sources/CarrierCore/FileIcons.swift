import Foundation

// The identity icon of a file (docs/specs/macos-app-redesign.md, story 45): a subset of Material Icon Theme (MIT)
// bundled as SVGs in `Resources/FileIcons`, with its licence next to them. Anything it does not cover gets the symbol of
// its category. `fileIcon` is the one entry point; the view only draws what it returns.

public enum FileIcon: Equatable {
    /// An SVG inside the bundle, by the name Material Icon Theme gives it.
    case bundled(name: String, url: URL)
    case symbol(String)
}

private let iconByExtension: [String: String] = {
    let table: [String: [String]] = [
        "typescript": ["ts"], "react_ts": ["tsx"], "javascript": ["js", "mjs", "cjs"], "react": ["jsx"],
        "json": ["json"], "markdown": ["md", "mdx", "markdown"], "yaml": ["yml", "yaml"], "css": ["css"],
        "html": ["html"], "swift": ["swift"], "python": ["py"], "go": ["go"], "rust": ["rs"],
        "console": ["sh", "bash", "zsh"], "database": ["sql"], "prisma": ["prisma"], "lock": ["lock"],
        "image": ["png", "jpg", "jpeg", "gif", "svg", "webp", "ico", "heic"],
    ]
    return Dictionary(uniqueKeysWithValues: table.flatMap { icon, extensions in extensions.map { ($0, icon) } })
}()

/// By the whole (lower-case) name, before the extension is looked at.
private let iconByName: [String: String] = [
    "dockerfile": "docker", "package-lock.json": "lock", "pnpm-lock.yaml": "lock",
]

/// The name of the bundled icon for a path, from its file name alone, or nil when the set does not cover it.
public func bundledIconName(_ path: String) -> String? {
    let name = path.lowercased().split(separator: "/").last.map(String.init) ?? ""
    if let known = iconByName[name] { return known }
    // A leading dot is part of the name, not an extension: `.gitignore` has none.
    guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return nil }
    return iconByExtension[String(name[name.index(after: dot)...])]
}

/// The icon of a path: the bundled one when there is one, else its category's symbol.
public func fileIcon(_ path: String) -> FileIcon {
    if let name = bundledIconName(path),
        let url = Bundle.module.url(forResource: name, withExtension: "svg", subdirectory: "FileIcons")
    {
        return .bundled(name: name, url: url)
    }
    return .symbol(fileCategory(path).symbol)
}

/// The upstream licence text that ships with the icons, shown from About's licences.
public var fileIconsLicenceURL: URL? {
    Bundle.module.url(forResource: "LICENSE", withExtension: nil, subdirectory: "FileIcons")
}
