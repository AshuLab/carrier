import Foundation

// Files handed to the chat by dropping them on the message box. The agent reads a file by its path with its own tools, so attaching one is
// putting its path in the message (docs/ explorations: attachments-options): a block of lines after what the person wrote, which the
// conversation reads back to show the files as chips under the bubble. The host moves each copy still in pending into the session when the
// message goes, and rewrites its path (src/chat/attachments.ts).

public enum AttachmentKind: Equatable, Sendable { case image, pdf, folder, log, code, data, archive, other }

public enum AttachmentProblem: Equatable, Sendable {
    case missing
    case tooBig(Int64)
    /// A file of Carrier's own folder (the engine's state and the chat's database): not for an agent.
    case carrierOwn
}

public struct AttachedFile: Equatable, Identifiable, Sendable {
    public let path: String
    public let kind: AttachmentKind
    /// Bytes of a file; nil for a folder.
    public let size: Int64?
    /// What a folder holds (its first level).
    public let items: Int?
    public let problem: AttachmentProblem?
    /// Where the person dropped it from, when what is at `path` is the copy Carrier keeps.
    public var source: String?

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
    public func detail(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        if let items { return Copy.chatAttachmentItems(count: items, bundle: bundle, locale: locale) }
        guard let size else { return "" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    /// Why it is not going, in a few words; nil when it goes.
    public func problemText(bundle: Bundle? = nil, locale: Locale = .current) -> String? {
        switch problem {
        case .missing?: Copy.chatAttachmentNotFound(bundle: bundle, locale: locale)
        case .tooBig(let bytes)?: Copy.chatAttachmentTooBig(size: ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file), bundle: bundle, locale: locale)
        case .carrierOwn?: Copy.chatAttachmentCarrierOwn(bundle: bundle, locale: locale)
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
    let places = CarrierPlaces(folder: carrierFolder)
    let own = [places.engine + "/", places.chatState + "/"].contains { path.hasPrefix($0) }
    if isFolder.boolValue {
        let items = (try? fileManager.contentsOfDirectory(atPath: path).filter { $0.hasPrefix(".") == false }.count) ?? 0
        return AttachedFile(path: path, kind: .folder, items: items, problem: own ? .carrierOwn : nil)
    }
    let size = ((try? fileManager.attributesOfItem(atPath: path)[.size]) as? NSNumber)?.int64Value ?? 0
    let problem: AttachmentProblem? = own ? .carrierOwn : size > attachmentSizeLimit ? .tooBig(size) : nil
    return AttachedFile(path: path, kind: attachmentKind(ofExtension: url.pathExtension), size: size, problem: problem)
}

/// A file the person dropped, as the chat holds it: a copy under `<carrier>/chat/pending/<id>/<name>`, so deleting or moving the original
/// leaves the conversation its file. A folder (or a file that cannot go) stays where it is, and the copy is not made.
public func attachedCopy(of url: URL, carrierFolder: String, fileManager: FileManager = .default) -> AttachedFile {
    var file = attachedFile(at: url, carrierFolder: carrierFolder, fileManager: fileManager)
    let source = url.standardizedFileURL.path
    if file.problem == nil, file.kind != .folder {
        let folder = URL(fileURLWithPath: attachmentsFolder(carrierFolder)).appendingPathComponent(UUID().uuidString)
        let copy = folder.appendingPathComponent(url.lastPathComponent)
        if (try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)) != nil, (try? fileManager.copyItem(at: url, to: copy)) != nil {
            file = attachedFile(at: copy, carrierFolder: carrierFolder, fileManager: fileManager)
        }
    }
    file.source = source
    return file
}

/// A picture dragged in as data and nothing else (a screenshot's thumbnail offers only that): written to a folder of its own, named as the Mac
/// names a screenshot, so that it goes as any file does. The caller attaches it (which copies it) and removes the folder.
public func droppedImageFile(_ data: Data, ext: String, now: Date = Date(), fileManager: FileManager = .default) -> URL? {
    let stamp = DateFormatter()
    stamp.locale = Locale(identifier: "en_US_POSIX")
    stamp.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
    let folder = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let file = folder.appendingPathComponent("Image \(stamp.string(from: now)).\(ext)")
    guard (try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)) != nil, (try? data.write(to: file)) != nil else { return nil }
    return file
}

/// The files about to go with a message, each with the copy Carrier keeps: one whose copy the host swept after a day in the box is copied again from
/// where the person dropped it, as the original is at this moment (an edited file goes in its new version). When the original cannot go either, the
/// file comes back with its problem (`.missing`, too big, Carrier's own), and `lostInRefresh` says so.
public func refreshedCopies(_ files: [AttachedFile], carrierFolder: String, fileManager: FileManager = .default) -> [AttachedFile] {
    files.map { file in
        guard let source = file.source, fileManager.fileExists(atPath: file.path) == false else { return file }
        return attachedCopy(of: URL(fileURLWithPath: source), carrierFolder: carrierFolder, fileManager: fileManager)
    }
}

/// A file that could go before `refreshedCopies` and cannot after it: the message would leave it out without a word, so the send waits for the person to see it.
public func lostInRefresh(_ before: [AttachedFile], _ after: [AttachedFile]) -> Bool {
    zip(before, after).contains { $0.problem == nil && $1.problem != nil }
}

/// Takes the copy of a file out again (the person removed its chip before sending); only ever something inside the pending folder.
public func discardAttachment(_ file: AttachedFile, carrierFolder: String, fileManager: FileManager = .default) {
    guard file.source != nil else { return }
    let folder = URL(fileURLWithPath: file.path).deletingLastPathComponent()
    guard folder.deletingLastPathComponent().standardizedFileURL.path == attachmentsFolder(carrierFolder) else { return }
    try? fileManager.removeItem(at: folder)
}

private func attachmentsFolder(_ carrierFolder: String) -> String { CarrierPlaces(folder: URL(fileURLWithPath: carrierFolder).standardizedFileURL.path).chatPending }

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
