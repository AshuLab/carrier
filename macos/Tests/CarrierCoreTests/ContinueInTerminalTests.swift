import Foundation
import Testing
@testable import CarrierCore

/// A scratch shared root with a folder inside, a configuration folder, a folder outside the root and fake harnesses.
private struct Scratch {
    let base: String
    let root: String
    let inside: String
    let config: String
    let outside: String
    let bin: String

    init() throws {
        let made = (NSTemporaryDirectory() as NSString).appendingPathComponent("carrier-continue-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: made, withIntermediateDirectories: true)
        let resolved = realpath(made, nil).map { String(cString: $0) }!  // /var is a link to /private/var
        base = resolved
        root = resolved + "/root"
        inside = root + "/clone"
        config = resolved + "/config"
        outside = resolved + "/outside"
        bin = resolved + "/bin"
        for folder in [inside, config, outside, bin] { try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true) }
        // Each fake harness writes what it was run with into the folder it ran in.
        for name in ["claude", "codex", "agy"] {
            let path = bin + "/" + name
            let body = "#!/bin/sh\nprintf '%s\\n' \"$PWD\" \"${CLAUDE_CONFIG_DIR-unset}\" \"${CODEX_HOME-unset}\" \"$0\" \"$@\" > ran.txt\n"
            try body.write(toFile: path, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        }
    }

    func remove() { try? FileManager.default.removeItem(atPath: base) }

    func descriptor(_ harness: String = "claude", id: String = "91d4be02-6a35-4c1e-9b7f-3e5a7c9d1f20", cwd: String? = nil, config: String? = nil) -> ResumeDescriptor {
        ResumeDescriptor(harness: harness, sessionId: id, cwd: cwd ?? inside, configDir: config)
    }

    func rejection(_ descriptor: ResumeDescriptor) -> ResumeRejection? {
        if case .failure(let rejection) = validateResume(descriptor, root: root) { rejection } else { nil }
    }
}

private let id = "91d4be02-6a35-4c1e-9b7f-3e5a7c9d1f20"

// MARK: the validator

@Test func aWellFormedDescriptorIsAccepted() throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    for harness in ["claude", "codex", "agy"] {
        let result = validateResume(scratch.descriptor(harness, config: scratch.config), root: scratch.root)
        #expect(result == .success(ValidResume(harness: harness, sessionId: id, cwd: scratch.inside, configDir: harness == "agy" ? nil : scratch.config)))
    }
    #expect(validateResume(scratch.descriptor(), root: scratch.root) == .success(ValidResume(harness: "claude", sessionId: id, cwd: scratch.inside)))
}

@Test(arguments: ["", "gemini", "Claude", "claude ", "claude; id", "sh", "../claude"])
func anUnknownHarnessIsRejected(harness: String) throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    #expect(scratch.rejection(scratch.descriptor(harness)) == .unknownHarness)
}

@Test(arguments: [
    "", "two words", "with space ", "it's", "say\"hi\"", "a\nb", "a\n", "$(id)", "`id`", "a;b", "a&b", "a|b", "a/b", "../x", "-n", "--help", "_x",
    "a\\b", "a$HOME", "caf\u{E9}", "a\0b", String(repeating: "a", count: 129),
])
func aSessionIdOutsideTheStrictPatternIsRejected(sessionId: String) throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    #expect(scratch.rejection(scratch.descriptor(id: sessionId)) == .badSessionId)
}

@Test(arguments: ["a1b2c3d4-0001-4000-8000-000000000002", "sess-1", "Abc_123", "7"])
func anIdentifierIsAccepted(sessionId: String) throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    #expect(scratch.rejection(scratch.descriptor(id: sessionId)) == nil)
}

@Test func aFolderThatIsNotInsideTheRootIsRejected() throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    #expect(scratch.rejection(scratch.descriptor(cwd: scratch.outside)) == .folderOutsideRoot)
    #expect(scratch.rejection(scratch.descriptor(cwd: scratch.root)) == .folderOutsideRoot)
    #expect(scratch.rejection(scratch.descriptor(cwd: "/")) == .folderOutsideRoot)
    // A sibling whose name starts like the root is not inside it.
    try FileManager.default.createDirectory(atPath: scratch.root + "-evil", withIntermediateDirectories: true)
    #expect(scratch.rejection(scratch.descriptor(cwd: scratch.root + "-evil")) == .folderOutsideRoot)
}

@Test func aPathWithDotDotIsRejectedEvenWhenItLandsInsideTheRoot() throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    #expect(scratch.rejection(scratch.descriptor(cwd: scratch.inside + "/../clone")) == .badFolder)
    #expect(scratch.rejection(scratch.descriptor(cwd: scratch.root + "/../outside")) == .badFolder)
    #expect(scratch.rejection(scratch.descriptor(cwd: scratch.inside, config: scratch.config + "/../config")) == .badConfigDir)
}

@Test func aSymlinkOutOfTheRootIsRejected() throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    try FileManager.default.createSymbolicLink(atPath: scratch.root + "/escape", withDestinationPath: scratch.outside)
    #expect(scratch.rejection(scratch.descriptor(cwd: scratch.root + "/escape")) == .folderOutsideRoot)
    // A symlink that stays inside is fine and is resolved.
    try FileManager.default.createSymbolicLink(atPath: scratch.root + "/alias", withDestinationPath: scratch.inside)
    #expect(validateResume(scratch.descriptor(cwd: scratch.root + "/alias"), root: scratch.root) == .success(ValidResume(harness: "claude", sessionId: id, cwd: scratch.inside)))
}

@Test(arguments: ["relative/path", "", "~/x", "\n"])
func aFolderThatIsNotAnAbsolutePathIsRejected(cwd: String) throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    #expect(scratch.rejection(scratch.descriptor(cwd: cwd)) == .badFolder)
}

@Test func aFolderThatDoesNotExistOrIsAFileIsRejected() throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    #expect(scratch.rejection(scratch.descriptor(cwd: scratch.root + "/missing")) == .badFolder)
    try "x".write(toFile: scratch.root + "/file", atomically: true, encoding: .utf8)
    #expect(scratch.rejection(scratch.descriptor(cwd: scratch.root + "/file")) == .badFolder)
    #expect(scratch.rejection(scratch.descriptor(cwd: scratch.inside + "\0")) == .badFolder)
}

@Test func aConfigurationFolderThatDoesNotExistIsRejected() throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    #expect(scratch.rejection(scratch.descriptor(config: scratch.base + "/nope")) == .badConfigDir)
    #expect(scratch.rejection(scratch.descriptor(config: "relative")) == .badConfigDir)
    #expect(scratch.rejection(scratch.descriptor("codex", config: scratch.base + "/nope")) == .badConfigDir)
}

@Test func aRootThatDoesNotExistAcceptsNothing() throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    #expect(validateResume(scratch.descriptor(), root: scratch.base + "/no-root") == .failure(.folderOutsideRoot))
}

// MARK: the script

@Test func theScriptForEachHarnessIsExactlyThis() throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    let path = "/tmp/carrier-X.command"
    let dir = scratch.config
    func script(_ harness: String, config: String?) throws -> String {
        let valid = try #require(try? validateResume(scratch.descriptor(harness, config: config), root: scratch.root).get())
        return resumeScript(valid, path: path)
    }
    let head = "#!/bin/zsh -il\nrm -f -- '/tmp/carrier-X.command'\ncd '\(scratch.inside)' || exit 1\n"
    #expect(try script("claude", config: dir) == head + "CLAUDE_CONFIG_DIR='\(dir)' claude --resume '\(id)'\n")
    #expect(try script("claude", config: nil) == head + "claude --resume '\(id)'\n")
    #expect(try script("codex", config: dir) == head + "CODEX_HOME='\(dir)' codex resume '\(id)'\n")
    #expect(try script("codex", config: nil) == head + "codex resume '\(id)'\n")
    #expect(try script("agy", config: dir) == head + "agy --conversation '\(id)'\n")
}

@Test func theCommandShownIsTheOneTheScriptRuns() throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    let valid = try #require(try? validateResume(scratch.descriptor("codex", config: scratch.config), root: scratch.root).get())
    #expect(resumeCommand(valid) == "cd '\(scratch.inside)' && CODEX_HOME='\(scratch.config)' codex resume '\(id)'")
}

/// Runs the generated script with `/bin/sh` and the fake harnesses; returns what the fake wrote in the folder it ran in.
private func run(_ script: String, scratch: Scratch, in folder: String, at path: String) throws -> [String] {
    try script.write(toFile: path, atomically: true, encoding: .utf8)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = [path]
    process.environment = ["PATH": scratch.bin + ":/usr/bin:/bin"]
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
    #expect(FileManager.default.fileExists(atPath: path) == false)  // it removed itself
    let ran = try String(contentsOfFile: folder + "/ran.txt", encoding: .utf8)
    return ran.split(separator: "\n", omittingEmptySubsequences: false).dropLast().map(String.init)
}

@Test(arguments: [
    "sp ace",
    "q'uote and \"double\"",
    "$(touch PWNED) `touch PWNED` ${HOME}",
    "semi; touch PWNED; && touch PWNED || | & > < ( ) # ! * ? ~",
    "back\\slash",
    "-n --help",
    "Jos\u{E9} \u{2603} \u{65E5}\u{672C}\u{8A9E}",
])
func aHostileFolderNameStaysInert(name: String) throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    let folder = scratch.root + "/" + name
    let config = scratch.base + "/" + name
    try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(atPath: config, withIntermediateDirectories: true)
    for harness in ["claude", "codex", "agy"] {
        let valid = try #require(try? validateResume(scratch.descriptor(harness, cwd: folder, config: config), root: scratch.root).get())
        let ran = try run(resumeScript(valid, path: scratch.base + "/s.command"), scratch: scratch, in: folder, at: scratch.base + "/s.command")
        let expected: [String] = switch harness {
        case "claude": [folder, config, "unset", scratch.bin + "/claude", "--resume", id]
        case "codex": [folder, "unset", config, scratch.bin + "/codex", "resume", id]
        default: [folder, "unset", "unset", scratch.bin + "/agy", "--conversation", id]
        }
        #expect(ran == expected)
    }
    // Nothing inside the names was executed anywhere under the scratch folder.
    let found = FileManager.default.enumerator(atPath: scratch.base)?.allObjects.compactMap { $0 as? String }.filter { $0.hasSuffix("PWNED") }
    #expect(found?.isEmpty == true)
}

// MARK: the writer and the opener

private final class RecordingOpener: TerminalOpener {
    var opened: [URL] = []
    var fails = false
    var seenMode: Int?
    var seenText: String?

    func open(_ script: URL) throws {
        if fails { throw ContinueError.notWritten }
        opened.append(script)
        seenMode = (try? FileManager.default.attributesOfItem(atPath: script.path)[.posixPermissions] as? Int) ?? nil
        seenText = try? String(contentsOf: script, encoding: .utf8)
    }
}

@Test func theScriptIsWrittenWith0700AnUnpredictableNameAndOpenedOnce() throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    let opener = RecordingOpener()
    let first = try continueInTerminal(scratch.descriptor(config: scratch.config), root: scratch.root, opener: opener, directory: scratch.base)
    let second = try continueInTerminal(scratch.descriptor(), root: scratch.root, opener: opener, directory: scratch.base)
    #expect(opener.opened == [first, second])
    #expect(first != second)
    #expect(first.deletingLastPathComponent().path == scratch.base)
    #expect(first.pathExtension == "command")
    #expect(first.lastPathComponent.hasPrefix("carrier-"))
    #expect(UUID(uuidString: String(first.deletingPathExtension().lastPathComponent.dropFirst("carrier-".count))) != nil)
    #expect(opener.seenMode == 0o700)
    #expect((try FileManager.default.attributesOfItem(atPath: first.path)[.posixPermissions] as? Int) == 0o700)
    let valid = try #require(try? validateResume(scratch.descriptor(), root: scratch.root).get())
    #expect(opener.seenText == resumeScript(valid, path: second.path))
}

@Test func aRejectedDescriptorWritesNothingAndOpensNothing() throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    let opener = RecordingOpener()
    #expect(throws: ContinueError.rejected(.folderOutsideRoot)) {
        try continueInTerminal(scratch.descriptor(cwd: scratch.outside), root: scratch.root, opener: opener, directory: scratch.base)
    }
    #expect(throws: ContinueError.rejected(.badSessionId)) {
        try continueInTerminal(scratch.descriptor(id: "$(id)"), root: scratch.root, opener: opener, directory: scratch.base)
    }
    #expect(opener.opened.isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.base).filter { $0.hasSuffix(".command") }.isEmpty)
}

@Test func aScriptThatCannotBeOpenedIsDeleted() throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    let opener = RecordingOpener()
    opener.fails = true
    #expect(throws: ContinueError.notWritten) {
        try continueInTerminal(scratch.descriptor(), root: scratch.root, opener: opener, directory: scratch.base)
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.base).filter { $0.hasSuffix(".command") }.isEmpty)
}

@Test func aFolderForTheScriptThatDoesNotExistIsAnError() throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    #expect(throws: ContinueError.notWritten) {
        try continueInTerminal(scratch.descriptor(), root: scratch.root, opener: RecordingOpener(), directory: scratch.base + "/missing")
    }
}

// MARK: the model

@Test func aRunningSessionHasNoDescriptorAndTheOthersKeepTheirs() {
    let descriptor = ResumeDescriptor(harness: "claude", sessionId: id, cwd: "/work/clone")
    func session(_ executionId: String, _ status: String) -> SessionsReply.Session {
        SessionsReply.Session(
            executionId: executionId, stage: "ship", role: "author", round: nil, agent: .init(harness: "claude", model: "m", provider: nil),
            status: status, startedAt: 0, finishedAt: nil, resume: descriptor
        )
    }
    // Even if the engine sent one for a running session (it does not), the app does not offer it.
    let sections = sessionList(SessionsReply(sessions: [session("a", "running"), session("b", "failed"), session("c", "finished")])).sections
    #expect(sections.map(\.resume) == [nil, descriptor, descriptor])
}

@Test func aFolderNameWithAControlCharacterIsRejected() throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    for name in ["tab\there", "new\nline"] {
        try FileManager.default.createDirectory(atPath: scratch.root + "/" + name, withIntermediateDirectories: true)
        #expect(scratch.rejection(scratch.descriptor(cwd: scratch.root + "/" + name)) == .badFolder)
    }
}
