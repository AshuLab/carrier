import Foundation

// Files handed to the chat by dropping them on the message box. The agent reads a file by its path with its own tools, so attaching one is
// putting its path in the message (docs/ explorations: attachments-options): a block of lines after what the person wrote, which the
// conversation reads back to show the files as chips under the bubble. Nothing of this reaches the host.

public enum AttachmentKind: Equatable { case image, pdf, folder, log, code, data, archive, other }

public enum AttachmentProblem: Equatable {
    case missing
    case tooBig(Int64)
    /// A file of Carrier's own folder (the engine's state and the chat's database): not for an agent.
    case carrierOwn
}

public struct AttachedFile: Equatable, Identifiable {
    public let path: String
    public let kind: AttachmentKind
    /// Bytes of a file; nil for a folder.
    public let size: Int64?
    /// What a folder holds (its first level).
    public let items: Int?
    public let problem: AttachmentProblem?

    public var id: String { path }
    public var name: String { (path as NSString).lastPathComponent }

    public init(path: String, kind: AttachmentKind, size: Int64? = nil, items: Int? = nil, problem: AttachmentProblem? = nil) {
        self.path = path
        self.kind = kind
        self.size = size
        self.items = items
        self.problem = problem
    }

    /// "48 KB", "14 items": under the name.
    public var detail: String {
        if let items { return items == 1 ? "1 item" : "\(items) items" }
        guard let size else { return "" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    /// Why it is not going, in a few words; nil when it goes.
    public var problemText: String? {
        switch problem {
        case .missing?: "Not found"
        case .tooBig(let bytes)?: "Too big · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
        case .carrierOwn?: "Carrier's own file"
        case nil: nil
        }
    }
}

/// A file this big is not handed over: an agent reading it would fill its context with it.
public let attachmentSizeLimit: Int64 = 25 * 1024 * 1024

private let kinds: [AttachmentKind: Set<String>] = [
    .image: ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp", "svg"],
    .pdf: ["pdf"],
    .log: ["log", "txt", "out", "err"],
    .code: ["swift", "ts", "tsx", "js", "jsx", "mjs", "py", "go", "rs", "rb", "java", "kt", "c", "h", "cpp", "hpp", "sh", "zsh", "sql", "html", "css", "md"],
    .data: ["json", "csv", "tsv", "yaml", "yml", "toml", "xml", "sqlite", "db", "plist"],
    .archive: ["zip", "tar", "gz", "tgz", "bz2", "xz", "7z"],
]

public func attachmentKind(ofExtension ext: String) -> AttachmentKind {
    let lower = ext.lowercased()
    return kinds.first { $0.value.contains(lower) }?.key ?? .other
}

/// What is at `url`, with why it cannot go when it cannot: it is gone, it is too big, or it is inside Carrier's own state.
public func attachedFile(at url: URL, carrierFolder: String, fileManager: FileManager = .default) -> AttachedFile {
    let path = url.standardizedFileURL.path
    var isFolder: ObjCBool = false
    guard fileManager.fileExists(atPath: path, isDirectory: &isFolder) else {
        return AttachedFile(path: path, kind: attachmentKind(ofExtension: url.pathExtension), problem: .missing)
    }
    let own = [carrierFolder + "/engine/", carrierFolder + "/chat/state/"].contains { path.hasPrefix($0) }
    if isFolder.boolValue {
        let items = (try? fileManager.contentsOfDirectory(atPath: path).filter { $0.hasPrefix(".") == false }.count) ?? 0
        return AttachedFile(path: path, kind: .folder, items: items, problem: own ? .carrierOwn : nil)
    }
    let size = ((try? fileManager.attributesOfItem(atPath: path)[.size]) as? NSNumber)?.int64Value ?? 0
    let problem: AttachmentProblem? = own ? .carrierOwn : size > attachmentSizeLimit ? .tooBig(size) : nil
    return AttachedFile(path: path, kind: attachmentKind(ofExtension: url.pathExtension), size: size, problem: problem)
}

private let attachmentsHeading = "Attached files:"

/// The message the agent gets: what the person wrote, then a line a file with its path (a folder's ends with a slash). The files that cannot
/// go are left out; without any, the text as it is.
public func messageWithAttachments(_ text: String, files: [AttachedFile]) -> String {
    let going = files.filter { $0.problem == nil }
    guard going.isEmpty == false else { return text }
    let lines = going.map { "- " + $0.path + ($0.kind == .folder ? "/" : "") }
    return text + "\n\n" + attachmentsHeading + "\n" + lines.joined(separator: "\n")
}

/// The message as the person wrote it and the paths of the files that came with it; the text itself when it ends with no such block.
public func splitAttachments(_ text: String) -> (text: String, paths: [String]) {
    let marker = "\n\n" + attachmentsHeading + "\n"
    let range = text.range(of: marker, options: .backwards)
    let body: Substring
    let block: Substring
    if let range {
        body = text[..<range.lowerBound]
        block = text[range.upperBound...]
    } else if text.hasPrefix(attachmentsHeading + "\n") {
        body = ""
        block = text.dropFirst(attachmentsHeading.count + 1)
    } else {
        return (text, [])
    }
    let lines = block.split(separator: "\n", omittingEmptySubsequences: false)
    let paths = lines.compactMap { $0.hasPrefix("- /") ? String($0.dropFirst(2)) : nil }
    guard paths.isEmpty == false, paths.count == lines.count else { return (text, []) }
    return (String(body), paths)
}
