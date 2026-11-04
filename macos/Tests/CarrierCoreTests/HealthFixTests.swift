import Foundation
import Testing
@testable import CarrierCore

private final class RecordingOpener: TerminalOpener {
    var opened: [URL] = []
    var texts: [String] = []

    func open(_ script: URL) throws {
        opened.append(script)
        texts.append((try? String(contentsOf: script, encoding: .utf8)) ?? "")
    }
}

private func scratch() throws -> String {
    let made = (NSTemporaryDirectory() as NSString).appendingPathComponent("carrier-fix-\(UUID().uuidString)")
    try FileManager.default.createDirectory(atPath: made, withIntermediateDirectories: true)
    return realpath(made, nil).map { String(cString: $0) }!
}

@Test func theListHasTheCommandsAndTheInstallationPages() {
    #expect(healthFix(.agent(harness: "claude"), .signedOut) == .command(["claude", "auth", "login"]))
    #expect(healthFix(.agent(harness: "codex"), .signedOut) == .command(["codex", "login"]))
    #expect(healthFix(.gh, .signedOut) == .command(["gh", "auth", "login"]))
    #expect(healthFix(.git, .missing) == .command(["xcode-select", "--install"]))
    #expect(healthFix(.agent(harness: "claude"), .signedOut)?.label == "claude auth login")
    for harness in ["claude", "codex"] {
        guard case .install(let url)? = healthFix(.agent(harness: harness), .missing) else { Issue.record("no install page for \(harness)"); continue }
        #expect(url.scheme == "https")
    }
    // a missing CLI has a link and no command
    #expect(healthFix(.agent(harness: "codex"), .missing)?.label == nil)
}

@Test func nothingElseHasAFix() {
    for state in [ToolState.ready, .unknown] {
        for tool in [HealthTool.agent(harness: "claude"), .agent(harness: "codex"), .gh, .git] { #expect(healthFix(tool, state) == nil) }
    }
    #expect(healthFix(.git, .signedOut) == nil)
    #expect(healthFix(.agent(harness: "agy"), .signedOut) == nil)
    #expect(healthFix(.agent(harness: "agy"), .missing) == nil)
}

@Test func theScriptIsExactlyThis() {
    #expect(fixScript(["claude", "auth", "login"], path: "/tmp/carrier-X.command") == "#!/bin/zsh -il\nrm -f -- '/tmp/carrier-X.command'\n'claude' 'auth' 'login'\n")
    #expect(fixScript(["xcode-select", "--install"], path: "/tmp/it's.command") == "#!/bin/zsh -il\nrm -f -- '/tmp/it'\\''s.command'\n'xcode-select' '--install'\n")
}

@Test func aFixIsWrittenAsAOneUseScriptAndOpenedOnce() throws {
    let directory = try scratch()
    defer { try? FileManager.default.removeItem(atPath: directory) }
    let opener = RecordingOpener()
    let url = try #require(try fixInTerminal(.gh, .signedOut, opener: opener, directory: directory))
    #expect(opener.opened == [url])
    #expect(url.deletingLastPathComponent().path == directory && url.pathExtension == "command" && url.lastPathComponent.hasPrefix("carrier-"))
    #expect(opener.texts == [fixScript(["gh", "auth", "login"], path: url.path)])
    #expect((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int) == 0o700)
}

@Test func aMissingCliAndAStateWithNoFixOpenNothing() throws {
    let directory = try scratch()
    defer { try? FileManager.default.removeItem(atPath: directory) }
    let opener = RecordingOpener()
    #expect(try fixInTerminal(.agent(harness: "claude"), .missing, opener: opener, directory: directory) == nil)
    #expect(try fixInTerminal(.gh, .ready, opener: opener, directory: directory) == nil)
    #expect(try fixInTerminal(.git, .unknown, opener: opener, directory: directory) == nil)
    #expect(opener.opened.isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory).isEmpty)
}

/// What a probe, the host or the doctor could hand back: the list has no key for it, so nothing is written, opened or run.
@Test(arguments: [
    "claude'; touch PWNED; '", "claude\ntouch PWNED", "$(touch PWNED)", "`touch PWNED`", "claude && touch PWNED", "claude ", "Claude", "",
    "claude\0", "../claude", "-n", "claude\"; touch PWNED; \"",
])
func aHostileValueFromAProbeRunsNone(value: String) throws {
    let directory = try scratch()
    defer { try? FileManager.default.removeItem(atPath: directory) }
    let opener = RecordingOpener()
    for state in [ToolState.signedOut, .missing, .ready, .unknown] {
        #expect(healthFix(.agent(harness: value), state) == nil)
        #expect(try fixInTerminal(.agent(harness: value), state, opener: opener, directory: directory) == nil)
    }
    #expect(opener.opened.isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory).isEmpty)
}

/// Runs each script of the list with `/bin/sh` and fake CLIs on the PATH: the CLI gets exactly the words of the list.
@Test func theScriptRunsExactlyTheCommandOfTheList() throws {
    let directory = try scratch()
    defer { try? FileManager.default.removeItem(atPath: directory) }
    let bin = directory + "/bin"
    try FileManager.default.createDirectory(atPath: bin, withIntermediateDirectories: true)
    for name in ["claude", "codex", "gh", "xcode-select"] {
        let body = "#!/bin/sh\nprintf '%s\\n' \"$0\" \"$@\" > \"$RAN\"\n"
        try body.write(toFile: bin + "/" + name, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin + "/" + name)
    }
    let cases: [(HealthTool, ToolState, String, [String])] = [
        (.agent(harness: "claude"), .signedOut, "claude", ["auth", "login"]),
        (.agent(harness: "codex"), .signedOut, "codex", ["login"]),
        (.gh, .signedOut, "gh", ["auth", "login"]),
        (.git, .missing, "xcode-select", ["--install"]),
    ]
    for (tool, state, name, arguments) in cases {
        let opener = RecordingOpener()
        let url = try #require(try fixInTerminal(tool, state, opener: opener, directory: directory))
        let ran = directory + "/ran-\(name).txt"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [url.path]
        process.environment = ["PATH": bin + ":/usr/bin:/bin", "RAN": ran]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(FileManager.default.fileExists(atPath: url.path) == false)  // it removed itself
        let lines = try String(contentsOfFile: ran, encoding: .utf8).split(separator: "\n").map(String.init)
        #expect(lines == [bin + "/" + name] + arguments)
    }
}
