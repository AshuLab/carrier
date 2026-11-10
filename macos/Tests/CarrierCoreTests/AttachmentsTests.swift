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
