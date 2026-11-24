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
    let made = (NSTemporaryDirectory() as NSString).appendingPathComponent("carrier-forge-\(UUID().uuidString)")
    try FileManager.default.createDirectory(atPath: made, withIntermediateDirectories: true)
    return realpath(made, nil).map { String(cString: $0) }!
}

@Test func theListHasAgentForgeAddAndNothingElse() throws {
    #expect(try forgeCommand("add") == ["agent-forge", "add"])
    #expect(fixScript(try forgeCommand("add"), path: "/tmp/carrier-X.command") == "#!/bin/zsh -il\nrm -f -- '/tmp/carrier-X.command'\n'agent-forge' 'add'\n")
}

/// Anything outside the list, as a registry, the config or the host could hand back, is refused and nothing is written or opened.
@Test(arguments: [
    "remove", "Add", "add ", " add", "", "add; touch PWNED", "add'; touch PWNED; '", "add\ntouch PWNED", "$(touch PWNED)", "`touch PWNED`",
    "add && touch PWNED", "add\0", "../add", "--help", "acme-author",
])
func aVerbOutsideTheListIsRefused(verb: String) {
    #expect(throws: ForgeCommandError.notInTheList) { try forgeCommand(verb) }
}

@Test func createABotIsWrittenAsAOneUseScriptAndOpenedOnce() throws {
    let directory = try scratch()
    defer { try? FileManager.default.removeItem(atPath: directory) }
    let opener = RecordingOpener()
    let url = try createBotInTerminal(opener: opener, directory: directory)
    #expect(opener.opened == [url])
    #expect(url.deletingLastPathComponent().path == directory && url.pathExtension == "command" && url.lastPathComponent.hasPrefix("carrier-"))
    #expect(opener.texts == [fixScript(["agent-forge", "add"], path: url.path)])
    #expect((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int) == 0o700)
}

/// Whatever the registry or the config holds, the script is the same: nothing read from them is part of the command.
@Test func theScriptDoesNotDependOnTheRegistry() throws {
    let directory = try scratch()
    defer { try? FileManager.default.removeItem(atPath: directory) }
    let hostile = #"{"agents": [{"name": "x'; touch PWNED; '"}, {"name": "$(touch PWNED)"}]}"#
    let registry = directory + "/agents.json"
    try hostile.write(toFile: registry, atomically: true, encoding: .utf8)
    let names = forgeBots(registry: currentForgeRegistry(environment: ["AGENT_FORGE_CONFIG": registry], home: "/nowhere")).names
    #expect(names.count == 2)
    let opener = RecordingOpener()
    let url = try createBotInTerminal(opener: opener, directory: directory)
    #expect(opener.texts == ["#!/bin/zsh -il\nrm -f -- '\(url.path)'\n'agent-forge' 'add'\n"])
}

@Test func theScriptRunsExactlyAgentForgeAdd() throws {
    let directory = try scratch()
    defer { try? FileManager.default.removeItem(atPath: directory) }
    let bin = directory + "/bin"
    try FileManager.default.createDirectory(atPath: bin, withIntermediateDirectories: true)
    try "#!/bin/sh\nprintf '%s\\n' \"$0\" \"$@\" > \"$RAN\"\n".write(toFile: bin + "/agent-forge", atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin + "/agent-forge")
    let url = try createBotInTerminal(opener: RecordingOpener(), directory: directory)
    let ran = directory + "/ran.txt"
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = [url.path]
    process.environment = ["PATH": bin + ":/usr/bin:/bin", "RAN": ran]
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
    #expect(FileManager.default.fileExists(atPath: url.path) == false)
    #expect(try String(contentsOfFile: ran, encoding: .utf8).split(separator: "\n").map(String.init) == [bin + "/agent-forge", "add"])
}

/// A bot made in Terminal shows at the next activation, which reads the registry again (`AgentsTabView.load`).
@Test func aBotAddedBetweenTwoActivationsIsListedByTheNext() throws {
    let directory = try scratch()
    defer { try? FileManager.default.removeItem(atPath: directory) }
    let registry = directory + "/agents.json"
    let environment = ["AGENT_FORGE_CONFIG": registry]
    let config = Data(#"{"profiles": {}, "agents": {}}"#.utf8)
    func activate() throws -> AgentsPage {
        try #require(agentsPage(config: config, providers: nil, bots: forgeBots(registry: currentForgeRegistry(environment: environment, home: "/nowhere"))))
    }
    try #"{"agents": [{"name": "acme-author"}]}"#.write(toFile: registry, atomically: true, encoding: .utf8)
    #expect(try activate().bots.names == ["acme-author"])
    try #"{"agents": [{"name": "acme-author"}, {"name": "acme-new"}]}"#.write(toFile: registry, atomically: true, encoding: .utf8)
    #expect(try activate().bots.names == ["acme-author", "acme-new"])
}
