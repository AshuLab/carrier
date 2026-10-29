import Testing
@testable import CarrierCore

private let complete = SetupSettings(
    carrier: "/n/bin/carrier", node: "/n/bin/node", path: "/usr/bin:/n/bin:/bin", configPath: "/h/.carrier/config.json"
)

@Test func theHostsCommandLineIsNodeCarrierChatHostWithNoConfig() throws {
    let command = try #require(startChatHostCommand(settings: complete, environment: ["HOME": "/h", "PATH": "/usr/bin"], home: "/h"))
    #expect(command.node == "/n/bin/node")
    #expect(command.arguments == ["/n/bin/carrier", "chat-host"])
}

@Test func theHostGetsTheEnginePathTheFolderAndKeepsTheRestOfTheEnvironment() throws {
    let command = try #require(startChatHostCommand(settings: complete, environment: ["HOME": "/h", "PATH": "/usr/bin"], home: "/h"))
    #expect(command.environment["PATH"] == "/n/bin:/usr/bin:/bin")
    #expect(command.environment["HOME"] == "/h")
    #expect(command.environment["CARRIER_HOME"] == "/h/.carrier")
}

@Test func theHostsLogAndSocketLiveUnderTheFoldersChatFolder() throws {
    let command = try #require(startChatHostCommand(settings: complete, environment: [:], home: "/h"))
    #expect(command.orchestratorDir == "/h/.carrier/chat")
    #expect(command.logsDir == "/h/.carrier/chat/logs")
    #expect(command.logPath == "/h/.carrier/chat/logs/app-start.log")
    #expect(command.socketPath == "/h/.carrier/chat/state/chat.sock")
}

@Test func carrierHomeInTheEnvironmentMovesTheFolder() throws {
    let command = try #require(startChatHostCommand(settings: complete, environment: ["CARRIER_HOME": "/scratch"], home: "/h"))
    #expect(command.environment["CARRIER_HOME"] == "/scratch")
    #expect(command.logPath == "/scratch/chat/logs/app-start.log")
    #expect(command.socketPath == "/scratch/chat/state/chat.sock")
}

@Test func withoutNodeOrCarrierThereIsNoHostCommandAndOnlyTheyAreNamed() {
    var settings = complete
    settings.node = ""
    #expect(startChatHostCommand(settings: settings, environment: [:], home: "/h") == nil)
    settings.carrier = ""
    settings.configPath = ""
    #expect(chatHostMissing(settings) == ["node", "carrier"])
}

@Test func anEmptyConfigPathNoLongerStopsTheHost() {
    var settings = complete
    settings.configPath = ""
    #expect(chatHostMissing(settings).isEmpty)
    #expect(startChatHostCommand(settings: settings, environment: [:], home: "/h") != nil)
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
