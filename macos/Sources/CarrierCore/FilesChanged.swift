import Foundation

// What the Files changed tab shows as plain values: the files grouped by agent session, each with a type and its lines
// (docs/specs/macos-app-redesign.md, story 23). The view maps them one to one.

// MARK: file types

/// The kind of file an icon stands for. The system's own file icons are not used (a TypeScript file comes out as a video).
public enum FileCategory: CaseIterable {
    case code, data, text, image, style, shell, lock, test, other

    /// The one place that says which symbol each category gets, so the source can be replaced later (story 45).
    public var symbol: String {
        switch self {
        case .code: "chevron.left.forwardslash.chevron.right"
        case .data: "curlybraces"
        case .text: "doc.text"
        case .image: "photo"
        case .style: "paintbrush"
        case .shell: "terminal"
        case .lock: "lock"
        case .test: "checkmark.seal"
        case .other: "doc"
        }
    }
}

private let categoryByExtension: [String: FileCategory] = {
    let table: [FileCategory: [String]] = [
        .code: ["ts", "tsx", "js", "jsx", "mjs", "cjs", "swift", "py", "rb", "go", "rs", "java", "kt", "c", "h", "cpp", "hpp", "cs", "php", "html", "vue", "svelte"],
        .data: ["json", "yml", "yaml", "toml", "xml", "plist", "ini", "cfg", "conf", "env", "csv", "sql", "prisma"],
        .text: ["md", "mdx", "markdown", "txt", "rst"],
        .image: ["png", "jpg", "jpeg", "gif", "svg", "webp", "ico", "heic"],
        .style: ["css", "scss", "sass", "less"],
        .shell: ["sh", "bash", "zsh", "fish", "command"],
        .lock: ["lock"],
    ]
    return Dictionary(uniqueKeysWithValues: table.flatMap { category, extensions in extensions.map { ($0, category) } })
}()

/// Files without an extension, and dotfiles, by their whole (lower-case) name.
private let categoryByName: [String: FileCategory] = [
    "dockerfile": .data, "makefile": .shell,
    "package-lock.json": .lock, "pnpm-lock.yaml": .lock,
    ".env": .data, ".zshrc": .shell, ".bashrc": .shell, ".zprofile": .shell, ".profile": .shell,
]

/// The category of a path, from its name alone. Names are not case sensitive.
public func fileCategory(_ path: String) -> FileCategory {
    let parts = path.lowercased().split(separator: "/").map(String.init)
    guard let name = parts.last else { return .other }
    if let known = categoryByName[name] { return known }
    let stem = name.split(separator: ".").first.map(String.init) ?? name
    let isTest =
        name.contains(".test.") || name.contains(".spec.") || stem.hasSuffix("_test") || stem.hasPrefix("test_")
        || parts.dropLast().contains { $0 == "tests" || $0 == "__tests__" }
    if isTest { return .test }
    // A leading dot is part of the name, not an extension: `.gitignore` has none.
    guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return .other }
    return categoryByExtension[String(name[name.index(after: dot)...])] ?? .other
}

// MARK: sections

public struct FileRow: Equatable {
    public var path: String
    /// Up to and including the last slash; empty for a file at the root.
    public var directory: String
    public var name: String
    public var category: FileCategory
    public var icon: FileIcon
    public var added: Int
    public var removed: Int
    /// The titles of the other working sections that edit this file too, when this section is working as well.
    public var alsoIn: [String]
}

public struct FileSection: Equatable {
    public var id: String
    public var title: String
    public var files: [FileRow]
    public var added: Int
    public var removed: Int
    /// Not merged into the epic yet.
    public var working: Bool
    /// Its file rows open to their fragment: a merged slice's and a fix round's do, a lane's not yet.
    public var opens: Bool
    /// Working sections open, merged ones folded.
    public var openByDefault: Bool { working }
}

public struct FilesChangedModel: Equatable {
    public var sections: [FileSection]
    /// Each path once, whatever number of sections touch it.
    public var fileCount: Int
    /// The lines of every section added up: a line edited in two sessions counts in both.
    public var added: Int
    public var removed: Int

    public var isEmpty: Bool { fileCount == 0 }
}

/// How many of five squares are green and how many red for a change of `added` and `removed` lines, as GitHub draws them: in
/// proportion, with at least one of each when both are above zero; none at all for no change.
public func diffSquares(added: Int, removed: Int) -> (green: Int, red: Int) {
    guard added + removed > 0 else { return (0, 0) }
    guard removed > 0 else { return (5, 0) }
    guard added > 0 else { return (0, 5) }
    let green = min(4, max(1, Int((5 * Double(added) / Double(added + removed)).rounded())))
    return (green, 5 - green)
}

public func filesChangedModel(_ reply: FilesReply?) -> FilesChangedModel {
    let source = reply?.sections ?? []
    let working = Set(source.filter { $0.kind != "merged" }.map(\.id))
    let titles = Dictionary(source.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })

    let sections = source.map { section -> FileSection in
        let isWorking = working.contains(section.id)
        let files = section.files.map { file -> FileRow in
            let slash = file.path.lastIndex(of: "/").map { file.path.index(after: $0) } ?? file.path.startIndex
            return FileRow(
                path: file.path,
                directory: String(file.path[..<slash]),
                name: String(file.path[slash...]),
                category: fileCategory(file.path),
                icon: fileIcon(file.path),
                added: file.added,
                removed: file.removed,
                alsoIn: isWorking ? file.alsoIn.filter { working.contains($0) }.map { titles[$0] ?? $0 } : []
            )
        }
        return FileSection(
            id: section.id, title: section.title, files: files,
            added: files.reduce(0) { $0 + $1.added }, removed: files.reduce(0) { $0 + $1.removed }, working: isWorking,
            opens: section.kind != "lane"
        )
    }
    return FilesChangedModel(
        sections: sections,
        fileCount: filesChangedCount(reply),
        added: sections.reduce(0) { $0 + $1.added },
        removed: sections.reduce(0) { $0 + $1.removed }
    )
}

// MARK: fragments

/// A file row opened to its fragment: the card's id in the `files` reply and the file's path.
public struct OpenFile: Hashable {
    public var section: String
    public var path: String

    public init(section: String, path: String) {
        self.section = section
        self.path = path
    }
}

/// What an opened file row draws under it: the rows `DiffView` draws (and whether the engine cut them), one line instead of rows,
/// or that the changes could not be loaded.
public enum FileFragment: Equatable {
    case rows([DiffRow], truncated: Bool)
    case note(String)
    case failed
}

public func fileFragment(_ reply: FileDiffReply) -> FileFragment {
    switch reply.note {
    case "binary": return .note("Binary file: no preview")
    case "too-big": return .note("Too big: no preview")
    case "no-changes", nil:
        guard let diff = cardDiff(reply.rows) else { return .note("No changes: the file is as it was") }
        return .rows(diff.rows, truncated: reply.truncated)
    default: return .note("No preview")
    }
}
