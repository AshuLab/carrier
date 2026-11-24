import Foundation
import Testing

@testable import CarrierCore

private func temporaryFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("attach-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

@Test func aFileIsDescribedByItsKindAndSizeAndAFolderByWhatItHolds() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let log = folder.appendingPathComponent("chat-host.log")
    try Data(count: 2048).write(to: log)
    let sub = folder.appendingPathComponent("fixtures")
    try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
    try Data().write(to: sub.appendingPathComponent("a.json"))
    try Data().write(to: sub.appendingPathComponent(".hidden"))

    let file = attachedFile(at: log, carrierFolder: "/nowhere")
    #expect(file.kind == .log && file.size == 2048 && file.problem == nil && file.name == "chat-host.log" && file.detail == "2 KB")
    let dir = attachedFile(at: sub, carrierFolder: "/nowhere")
    #expect(dir.kind == .folder && dir.items == 1 && dir.detail == "1 item" && dir.problem == nil)
}

@Test func aFileThatCannotGoSaysWhy() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let gone = attachedFile(at: folder.appendingPathComponent("gone.pdf"), carrierFolder: "/nowhere")
    #expect(gone.problem == .missing && gone.problemText == "Not found" && gone.kind == .pdf)
    // Carrier's own state: the database of the chat and the engine's folder
    let state = folder.appendingPathComponent("chat/state")
    try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
    let db = state.appendingPathComponent("chat.db")
    try Data(count: 10).write(to: db)
    #expect(attachedFile(at: db, carrierFolder: folder.standardizedFileURL.path).problem == .carrierOwn)
    #expect(AttachedFile(path: "/x/big.sqlite", kind: .data, size: 640 << 20, problem: .tooBig(640 << 20)).problemText?.hasPrefix("Too big · 6") == true)
}

@Test func theKindComesFromTheExtension() {
    #expect(attachmentKind(ofExtension: "PNG") == .image && attachmentKind(ofExtension: "swift") == .code && attachmentKind(ofExtension: "zip") == .archive)
    #expect(attachmentKind(ofExtension: "xyz") == .other && attachmentKind(ofExtension: "") == .other)
}

@Test func theMessageCarriesThePathsOfTheFilesThatGoAndReadsThemBack() {
    let files = [
        AttachedFile(path: "/Users/d/chat-host.log", kind: .log, size: 10), AttachedFile(path: "/Users/d/fixtures", kind: .folder, items: 3),
        AttachedFile(path: "/Users/d/huge.bin", kind: .other, size: 1, problem: .tooBig(99 << 20)),
    ]
    let message = messageWithAttachments("Look at why it fails", files: files)
    #expect(message == "Look at why it fails\n\nAttached files:\n- /Users/d/chat-host.log\n- /Users/d/fixtures/")
    let back = splitAttachments(message)
    #expect(back.text == "Look at why it fails" && back.paths == ["/Users/d/chat-host.log", "/Users/d/fixtures/"])
    #expect(messageWithAttachments("hi", files: []) == "hi" && messageWithAttachments("hi", files: [files[2]]) == "hi")
}

@Test func aTextThatLooksLikeTheBlockButIsNotOneIsLeftAlone() {
    #expect(splitAttachments("plain").paths.isEmpty)
    let prose = "See below\n\nAttached files:\n- this is not a path\n- /ok"
    #expect(splitAttachments(prose) == (prose, []))
    #expect(splitAttachments("Attached files:\n- /a/b").paths == ["/a/b"] && splitAttachments("Attached files:\n- /a/b").text.isEmpty)
}

@Test func aDroppedFileIsKeptInCarriersFolderAndSurvivesItsOriginal() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let carrier = folder.appendingPathComponent("carrier").standardizedFileURL.path
    let original = folder.appendingPathComponent("shot.png")
    try Data(count: 64).write(to: original)

    let kept = attachedCopy(of: original, carrierFolder: carrier)
    #expect(kept.path.hasPrefix(carrier + "/chat/pending/") && kept.name == "shot.png" && kept.kind == .image && kept.source == original.standardizedFileURL.path)
    try FileManager.default.removeItem(at: original)
    #expect(FileManager.default.fileExists(atPath: kept.path))

    // taking its chip out takes the copy out
    discardAttachment(kept, carrierFolder: carrier)
    #expect(FileManager.default.fileExists(atPath: kept.path) == false)

    // a folder stays where it is, and nothing outside the pending folder is ever deleted
    let sub = folder.appendingPathComponent("fixtures")
    try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
    let dir = attachedCopy(of: sub, carrierFolder: carrier)
    #expect(dir.path == sub.standardizedFileURL.path)
    discardAttachment(dir, carrierFolder: carrier)
    #expect(FileManager.default.fileExists(atPath: sub.path))
}

@Test func aCopyTheHostSweptIsMadeAgainFromItsSourceAndWhenThatIsGoneItSaysSo() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let carrier = folder.appendingPathComponent("carrier").standardizedFileURL.path
    let original = folder.appendingPathComponent("log.txt")
    try Data("hello".utf8).write(to: original)
    let kept = attachedCopy(of: original, carrierFolder: carrier)

    // a copy that is still there stays as it is
    #expect(refreshedCopies([kept], carrierFolder: carrier) == [kept])

    // the host swept it after a day: the same file comes back, in a new copy
    try FileManager.default.removeItem(atPath: kept.path)
    let again = try #require(refreshedCopies([kept], carrierFolder: carrier).first)
    #expect(again.path != kept.path && again.path.hasPrefix(carrier + "/chat/pending/") && again.problem == nil && again.source == kept.source)
    #expect(try String(contentsOfFile: again.path, encoding: .utf8) == "hello")

    // the original is gone too: it cannot go, and the message leaves it out
    try FileManager.default.removeItem(atPath: again.path)
    try FileManager.default.removeItem(at: original)
    let goneFiles = refreshedCopies([again], carrierFolder: carrier)
    let gone = try #require(goneFiles.first)
    #expect(gone.problem == .missing)
    #expect(messageWithAttachments("hi", files: [gone]) == "hi")
    // that is a loss to say before sending; a file that already said its problem, or one made again, is not
    #expect(lostInRefresh([again], goneFiles))
    #expect(lostInRefresh([gone], goneFiles) == false)
    #expect(lostInRefresh([kept], [again]) == false)

    // a file with no copy (a folder, a file that stayed where it is) is never touched
    let sub = folder.appendingPathComponent("fixtures")
    try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
    let dir = attachedCopy(of: sub, carrierFolder: carrier)
    #expect(refreshedCopies([dir], carrierFolder: carrier) == [dir])
}

@Test func aPictureDraggedAsDataIsWrittenToAFileNamedByItsTime() throws {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let file = try #require(droppedImageFile(Data([1, 2, 3]), ext: "png", now: now))
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    #expect(file.pathExtension == "png" && file.lastPathComponent.hasPrefix("Image 2023-11-"))
    #expect(try Data(contentsOf: file) == Data([1, 2, 3]))
}
