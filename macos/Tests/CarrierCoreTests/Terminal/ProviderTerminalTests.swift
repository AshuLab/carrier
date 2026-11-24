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
    let made = (NSTemporaryDirectory() as NSString).appendingPathComponent("carrier-provider-\(UUID().uuidString)")
    try FileManager.default.createDirectory(atPath: made, withIntermediateDirectories: true)
    return realpath(made, nil).map { String(cString: $0) }!
}

@Test func theListHasTheCommandOfEachHarnessAndAction() throws {
    #expect(try providerCommand(.signIn, harness: "claude") == "'claude' '/login'")
    #expect(try providerCommand(.signIn, harness: "claude", configDir: "/Users/me/.claude-work") == "CLAUDE_CONFIG_DIR='/Users/me/.claude-work' 'claude' '/login'")
    #expect(try providerCommand(.signIn, harness: "codex") == "'codex' 'login'")
    #expect(try providerCommand(.signIn, harness: "codex", configDir: "/Users/me/.codex-work") == "CODEX_HOME='/Users/me/.codex-work' 'codex' 'login'")
    #expect(try providerCommand(.signIn, harness: "agy") == "'agy'")
    // Antigravity has no variable, so a folder is not carried
    #expect(try providerCommand(.signIn, harness: "agy", configDir: "/Users/me/.agy") == "'agy'")
    for harness in ["claude", "codex", "agy"] {
        #expect(try providerCommand(.update, harness: harness) == "'\(harness)' 'update'")
        // an update is of the tool, not of an account: no folder in it
        #expect(try providerCommand(.update, harness: harness, configDir: "/Users/me/.x") == "'\(harness)' 'update'")
    }
}

@Test func anAccountsCommandIsTheBinaryThatRuns() throws {
    #expect(try providerCommand(.signIn, harness: "claude", command: "/opt/tools/claude-2", configDir: "/Users/me/.c") == "CLAUDE_CONFIG_DIR='/Users/me/.c' '/opt/tools/claude-2' '/login'")
    #expect(try providerCommand(.signIn, harness: "codex", command: "/opt/tools/codex") == "'/opt/tools/codex' 'login'")
    #expect(try providerCommand(.update, harness: "agy", command: "/opt/tools/agy") == "'/opt/tools/agy' 'update'")
}

@Test func aRelativeFolderOrBinaryAndAHarnessOrActionOutsideTheListAreRefused() throws {
    for folder in ["", "relative", "./here", "~/.claude", "../up", "/ok\0no", "/ok\nno"] {
        #expect(throws: ProviderCommandError.badFolder) { try providerCommand(.signIn, harness: "claude", configDir: folder) }
        #expect(throws: ProviderCommandError.badFolder) { try providerCommand(.signIn, harness: "codex", configDir: folder) }
    }
    for binary in ["", "claude", "bin/claude", "~/claude", "/ok\nno"] {
        #expect(throws: ProviderCommandError.badCommand) { try providerCommand(.signIn, harness: "claude", command: binary) }
        #expect(throws: ProviderCommandError.badCommand) { try providerCommand(.update, harness: "claude", command: binary) }
    }
    for harness in ["", "Claude", "claude ", "claude'; touch PWNED; '", "$(touch PWNED)", "gemini", "lmstudio", "../claude", "-n"] {
        #expect(throws: ProviderCommandError.unknownHarness) { try providerCommand(.signIn, harness: harness) }
        #expect(throws: ProviderCommandError.unknownHarness) { try providerCommand(.update, harness: harness) }
    }
    for action in ["", "signin", "check", "remove", "update; touch PWNED", "Update"] { #expect(ProviderAction(rawValue: action) == nil) }
}

@Test func aRefusalWritesAndOpensNothing() throws {
    let directory = try scratch()
    defer { try? FileManager.default.removeItem(atPath: directory) }
    let opener = RecordingOpener()
    #expect(throws: ProviderCommandError.badFolder) { try providerInTerminal(.signIn, harness: "claude", configDir: "relative", opener: opener, directory: directory) }
    #expect(throws: ProviderCommandError.unknownHarness) { try providerInTerminal(.update, harness: "gemini", opener: opener, directory: directory) }
    #expect(opener.opened.isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory).isEmpty)
}

@Test func aProviderActionIsWrittenAsAOneUseScriptAndOpenedOnce() throws {
    let directory = try scratch()
    defer { try? FileManager.default.removeItem(atPath: directory) }
    let opener = RecordingOpener()
    let url = try providerInTerminal(.signIn, harness: "codex", configDir: "/Users/me/.codex-work", opener: opener, directory: directory)
    #expect(opener.opened == [url])
    #expect(url.deletingLastPathComponent().path == directory && url.pathExtension == "command" && url.lastPathComponent.hasPrefix("carrier-"))
    #expect(opener.texts == ["#!/bin/zsh -il\nrm -f -- '\(url.path)'\nCODEX_HOME='/Users/me/.codex-work' 'codex' 'login'\n"])
    #expect((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int) == 0o700)
}

/// Runs the script with `/bin/sh` and a fake CLI in a folder with spaces and a single quote: the CLI gets the folder whole, in its variable.
@Test func aFolderWithSpacesAndAQuoteReachesTheCliWhole() throws {
    let directory = try scratch()
    defer { try? FileManager.default.removeItem(atPath: directory) }
    let folder = directory + "/it's a folder; touch PWNED $(touch PWNED)"
    try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    let bin = directory + "/bin dir"
    try FileManager.default.createDirectory(atPath: bin, withIntermediateDirectories: true)
    let body = "#!/bin/sh\nprintf '%s\\n' \"$0\" \"$CLAUDE_CONFIG_DIR\" \"$CODEX_HOME\" \"$@\" > \"$RAN\"\n"
    for name in ["claude", "codex", "agy"] {
        try body.write(toFile: bin + "/" + name, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin + "/" + name)
    }
    let cases: [(ProviderAction, String, String?, String?, [String])] = [
        (.signIn, "claude", folder, nil, [bin + "/claude", folder, "", "/login"]),
        (.signIn, "codex", folder, nil, [bin + "/codex", "", folder, "login"]),
        (.signIn, "agy", nil, nil, [bin + "/agy", "", ""]),
        (.update, "claude", nil, nil, [bin + "/claude", "", "", "update"]),
        // the account's own binary, by absolute path, with a quote and spaces in it
        (.signIn, "claude", folder, bin + "/claude", [bin + "/claude", folder, "", "/login"]),
    ]
    for (action, harness, configDir, command, expected) in cases {
        let opener = RecordingOpener()
        let url = try providerInTerminal(action, harness: harness, command: command, configDir: configDir, opener: opener, directory: directory)
        let ran = directory + "/ran.txt"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [url.path]
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        process.environment = ["PATH": bin + ":/usr/bin:/bin", "RAN": ran]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(FileManager.default.fileExists(atPath: url.path) == false)
        #expect(try String(contentsOfFile: ran, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false).dropLast().map(String.init) == expected)
        try? FileManager.default.removeItem(atPath: ran)
    }
    #expect(FileManager.default.fileExists(atPath: directory + "/PWNED") == false)
}

@Test func theFixtureOpenerSaysTheLineAndRemovesTheScript() throws {
    let directory = try scratch()
    defer { try? FileManager.default.removeItem(atPath: directory) }
    var said: [String] = []
    let url = try providerInTerminal(.update, harness: "claude", opener: FixtureTerminalOpener { said.append($0) }, directory: directory)
    #expect(said == ["'claude' 'update'"])
    #expect(FileManager.default.fileExists(atPath: url.path) == false)
}
