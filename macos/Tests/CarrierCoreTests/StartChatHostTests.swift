import Testing
@testable import CarrierCore

private let complete = SetupSettings(
    carrier: "/n/bin/carrier", node: "/n/bin/node", path: "/usr/bin:/n/bin:/bin", configPath: "/h/.carrier/config.json"
)

@Test func theHostsCommandLineIsNodeCarrierChatHostAndTheConfig() throws {
    let command = try #require(startChatHostCommand(settings: complete, root: "/h/.solve", environment: ["HOME": "/h", "PATH": "/usr/bin"]))
    #expect(command.node == "/n/bin/node")
    #expect(command.arguments == ["/n/bin/carrier", "chat-host", "--config", "/h/.carrier/config.json"])
}

@Test func theHostGetsTheEnginePathAndKeepsTheRestOfTheEnvironment() throws {
    let command = try #require(startChatHostCommand(settings: complete, root: "/h/.solve", environment: ["HOME": "/h", "PATH": "/usr/bin"]))
    #expect(command.environment["PATH"] == "/n/bin:/usr/bin:/bin")
    #expect(command.environment["HOME"] == "/h")
}

@Test func theHostsLogAndSocketLiveUnderTheRootsChatFolder() throws {
    let command = try #require(startChatHostCommand(settings: complete, root: "/h/.solve", environment: [:]))
    #expect(command.orchestratorDir == "/h/.solve/chat")
    #expect(command.logsDir == "/h/.solve/chat/logs")
    #expect(command.logPath == "/h/.solve/chat/logs/app-start.log")
    #expect(command.socketPath == "/h/.solve/chat/chat.sock")
}

@Test func withoutNodeCarrierOrAConfigPathThereIsNoHostCommand() {
    var settings = complete
    settings.node = ""
    #expect(startChatHostCommand(settings: settings, root: "/h/.solve", environment: [:]) == nil)
}

@Test func theHostStartsOnlyWhenASessionIsStartingAndNothingAnswersOrRuns() {
    func decide(session: Bool = true, answers: Bool = false, running: Bool = false, fixture: Bool = false) -> Bool {
        shouldStartChatHost(startingSession: session, hostAnswers: answers, startRunning: running, fixture: fixture)
    }
    #expect(decide())
    #expect(decide(session: false) == false)
    #expect(decide(answers: true) == false)
    #expect(decide(running: true) == false)
    #expect(decide(fixture: true) == false)
}

@Test func theFailureTextNamesTheHost() {
    #expect(startFailureText(.exited(1), name: "The chat host").hasPrefix("The chat host exited with code 1"))
}
