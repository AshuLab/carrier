import Foundation
import Testing
@testable import CarrierCore

/// A scratch engine folder with a folder inside, a configuration folder, a folder outside it and fake harnesses.
private struct Scratch {
    let base: String
    let engine: String
    let inside: String
    let config: String
    let outside: String
    let bin: String

    init() throws {
        let made = (NSTemporaryDirectory() as NSString).appendingPathComponent("carrier-continue-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: made, withIntermediateDirectories: true)
        let resolved = realpath(made, nil).map { String(cString: $0) }!  // /var is a link to /private/var
        base = resolved
        engine = resolved + "/engine"
        inside = engine + "/clone"
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
        if case .failure(let rejection) = validateResume(descriptor, engine: engine) { rejection } else { nil }
    }
}

private let id = "91d4be02-6a35-4c1e-9b7f-3e5a7c9d1f20"

// MARK: the validator

@Test func aWellFormedDescriptorIsAccepted() throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    for harness in ["claude", "codex", "agy"] {
        let result = validateResume(scratch.descriptor(harness, config: scratch.config), engine: scratch.engine)
        #expect(result == .success(ValidResume(harness: harness, sessionId: id, cwd: scratch.inside, configDir: harness == "agy" ? nil : scratch.config)))
    }
    #expect(validateResume(scratch.descriptor(), engine: scratch.engine) == .success(ValidResume(harness: "claude", sessionId: id, cwd: scratch.inside)))
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

@Test func aFolderThatIsNotInsideTheEngineFolderIsRejected() throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    #expect(scratch.rejection(scratch.descriptor(cwd: scratch.outside)) == .folderOutsideEngine)
    #expect(scratch.rejection(scratch.descriptor(cwd: scratch.engine)) == .folderOutsideEngine)
    #expect(scratch.rejection(scratch.descriptor(cwd: "/")) == .folderOutsideEngine)
    // A sibling whose name starts like the engine folder is not inside it.
    try FileManager.default.createDirectory(atPath: scratch.engine + "-evil", withIntermediateDirectories: true)
    #expect(scratch.rejection(scratch.descriptor(cwd: scratch.engine + "-evil")) == .folderOutsideEngine)
}

@Test func aPathWithDotDotIsRejectedEvenWhenItLandsInsideTheEngineFolder() throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    #expect(scratch.rejection(scratch.descriptor(cwd: scratch.inside + "/../clone")) == .badFolder)
    #expect(scratch.rejection(scratch.descriptor(cwd: scratch.engine + "/../outside")) == .badFolder)
    #expect(scratch.rejection(scratch.descriptor(cwd: scratch.inside, config: scratch.config + "/../config")) == .badConfigDir)
}

@Test func aSymlinkOutOfTheEngineFolderIsRejected() throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    try FileManager.default.createSymbolicLink(atPath: scratch.engine + "/escape", withDestinationPath: scratch.outside)
    #expect(scratch.rejection(scratch.descriptor(cwd: scratch.engine + "/escape")) == .folderOutsideEngine)
    // A symlink that stays inside is fine and is resolved.
    try FileManager.default.createSymbolicLink(atPath: scratch.engine + "/alias", withDestinationPath: scratch.inside)
    #expect(validateResume(scratch.descriptor(cwd: scratch.engine + "/alias"), engine: scratch.engine) == .success(ValidResume(harness: "claude", sessionId: id, cwd: scratch.inside)))
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
    #expect(scratch.rejection(scratch.descriptor(cwd: scratch.engine + "/missing")) == .badFolder)
    try "x".write(toFile: scratch.engine + "/file", atomically: true, encoding: .utf8)
    #expect(scratch.rejection(scratch.descriptor(cwd: scratch.engine + "/file")) == .badFolder)
    #expect(scratch.rejection(scratch.descriptor(cwd: scratch.inside + "\0")) == .badFolder)
}

@Test func aConfigurationFolderThatDoesNotExistIsRejected() throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    #expect(scratch.rejection(scratch.descriptor(config: scratch.base + "/nope")) == .badConfigDir)
    #expect(scratch.rejection(scratch.descriptor(config: "relative")) == .badConfigDir)
    #expect(scratch.rejection(scratch.descriptor("codex", config: scratch.base + "/nope")) == .badConfigDir)
}

@Test func anEngineFolderThatDoesNotExistAcceptsNothing() throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    #expect(validateResume(scratch.descriptor(), engine: scratch.base + "/no-engine") == .failure(.folderOutsideEngine))
}

// MARK: the command and embedded launch

@Test func theCommandForEachHarnessIsExactlyThis() throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    let dir = scratch.config
    func command(_ harness: String, config: String?) throws -> String {
        let valid = try #require(try? validateResume(scratch.descriptor(harness, config: config), engine: scratch.engine).get())
        return resumeCommand(valid)
    }
    let cd = "cd '\(scratch.inside)' && "
    #expect(try command("claude", config: dir) == cd + "CLAUDE_CONFIG_DIR='\(dir)' claude --resume '\(id)'")
    #expect(try command("claude", config: nil) == cd + "claude --resume '\(id)'")
    #expect(try command("codex", config: dir) == cd + "CODEX_HOME='\(dir)' codex resume '\(id)'")
    #expect(try command("codex", config: nil) == cd + "codex resume '\(id)'")
    #expect(try command("agy", config: dir) == cd + "agy --conversation '\(id)'")
}

/// Runs the shell command with `/bin/sh` and the fake harnesses; returns what the fake wrote in the folder it ran in.
private func run(_ command: String, scratch: Scratch, in folder: String) throws -> [String] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", command]
    process.environment = ["PATH": scratch.bin + ":/usr/bin:/bin"]
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
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
    let folder = scratch.engine + "/" + name
    let config = scratch.base + "/" + name
    try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(atPath: config, withIntermediateDirectories: true)
    for harness in ["claude", "codex", "agy"] {
        let valid = try #require(try? validateResume(scratch.descriptor(harness, cwd: folder, config: config), engine: scratch.engine).get())
        let ran = try run(resumeCommand(valid), scratch: scratch, in: folder)
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

// MARK: the shared script opener

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

@Test func openScriptWrites0700WithAnUnpredictableNameAndOpensOnce() throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    let opener = RecordingOpener()
    let first = try openScript({ "#!/bin/zsh -il\nrm -f -- \($0)\n" }, opener: opener, directory: scratch.base)
    let second = try openScript({ "#!/bin/zsh -il\necho \($0)\n" }, opener: opener, directory: scratch.base)
    #expect(opener.opened == [first, second])
    #expect(first != second)
    #expect(first.deletingLastPathComponent().path == scratch.base)
    #expect(first.pathExtension == "command")
    #expect(first.lastPathComponent.hasPrefix("carrier-"))
    #expect(UUID(uuidString: String(first.deletingPathExtension().lastPathComponent.dropFirst("carrier-".count))) != nil)
    #expect(opener.seenMode == 0o700)
    #expect((try FileManager.default.attributesOfItem(atPath: first.path)[.posixPermissions] as? Int) == 0o700)
    #expect(opener.seenText == "#!/bin/zsh -il\necho \(second.path)\n")
}

@Test func aScriptThatCannotBeOpenedIsDeleted() throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    let opener = RecordingOpener()
    opener.fails = true
    #expect(throws: ContinueError.notWritten) {
        try openScript({ _ in "#!/bin/sh\n" }, opener: opener, directory: scratch.base)
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.base).filter { $0.hasSuffix(".command") }.isEmpty)
}

@Test func aFolderForTheScriptThatDoesNotExistIsAnError() throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    #expect(throws: ContinueError.notWritten) {
        try openScript({ _ in "#!/bin/sh\n" }, opener: RecordingOpener(), directory: scratch.base + "/missing")
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
    #expect(sections.map(\.resume) == [descriptor, descriptor, nil])
}

@Test func aFolderNameWithAControlCharacterIsRejected() throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    for name in ["tab\there", "new\nline"] {
        try FileManager.default.createDirectory(atPath: scratch.engine + "/" + name, withIntermediateDirectories: true)
        #expect(scratch.rejection(scratch.descriptor(cwd: scratch.engine + "/" + name)) == .badFolder)
    }
}

@Test func embeddedResumeLaunchScopesEnvAndCommandForEachHarness() throws {
    let scratch = try Scratch()
    defer { scratch.remove() }

    let claude = try validateResume(scratch.descriptor("claude", config: scratch.config), engine: scratch.engine).get()
    let claudeLaunch = embeddedResumeLaunch(claude)
    #expect(claudeLaunch.workingDirectory == scratch.inside)
    #expect(claudeLaunch.envVars == ["CLAUDE_CONFIG_DIR": scratch.config])
    #expect(claudeLaunch.command == #"/bin/zsh -il -c 'claude --resume '\''\#(id)'\'''"#)
    #expect(claudeLaunch.displayCommand == resumeCommand(claude))

    let codex = try validateResume(scratch.descriptor("codex", config: scratch.config), engine: scratch.engine).get()
    let codexLaunch = embeddedResumeLaunch(codex)
    #expect(codexLaunch.workingDirectory == scratch.inside)
    #expect(codexLaunch.envVars == ["CODEX_HOME": scratch.config])
    #expect(codexLaunch.command == #"/bin/zsh -il -c 'codex resume '\''\#(id)'\'''"#)
    #expect(codexLaunch.displayCommand == resumeCommand(codex))

    let agy = try validateResume(scratch.descriptor("agy", config: scratch.config), engine: scratch.engine).get()
    let agyLaunch = embeddedResumeLaunch(agy)
    #expect(agyLaunch.workingDirectory == scratch.inside)
    #expect(agyLaunch.envVars.isEmpty)
    #expect(agyLaunch.command == #"/bin/zsh -il -c 'agy --conversation '\''\#(id)'\'''"#)
    #expect(agyLaunch.displayCommand == resumeCommand(agy))
}
