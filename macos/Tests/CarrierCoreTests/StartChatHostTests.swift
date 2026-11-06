import Testing
@testable import CarrierCore

private let complete = SetupSettings(
    node: "/n/bin/node", path: "/usr/bin:/n/bin:/bin"
)

private let homebrew = "/opt/homebrew/bin/carrier"

@Test func aBinaryRunsItselfWithChatHostAndNoNode() throws {
    let command = try #require(startChatHostCommand(settings: SetupSettings(path: "/usr/bin"), carrier: homebrew, environment: ["HOME": "/h", "PATH": "/usr/bin"], home: "/h"))
    #expect(command.program == homebrew)
    #expect(command.arguments == ["chat-host"])
}

@Test func aScriptRunsUnderNodeWithChatHost() throws {
    let command = try #require(startChatHostCommand(settings: complete, carrier: "/work/carrier/main.ts", environment: ["HOME": "/h", "PATH": "/usr/bin"], home: "/h"))
    #expect(command.program == "/n/bin/node")
    #expect(command.arguments == ["/work/carrier/main.ts", "chat-host"])
}

@Test func theHostGetsTheEnginePathTheFolderAndKeepsTheRestOfTheEnvironment() throws {
    let command = try #require(startChatHostCommand(settings: complete, carrier: homebrew, environment: ["HOME": "/h", "PATH": "/usr/bin"], home: "/h"))
    #expect(command.environment["PATH"] == "/n/bin:/usr/bin:/bin:/opt/homebrew/bin")
    #expect(command.environment["HOME"] == "/h")
    #expect(command.environment["CARRIER_HOME"] == "/h/.carrier")
}

@Test func theHostsLogAndSocketLiveUnderTheFoldersChatFolder() throws {
    let command = try #require(startChatHostCommand(settings: complete, carrier: homebrew, environment: [:], home: "/h"))
    #expect(command.processDir == "/h/.carrier/chat")
    #expect(command.logsDir == "/h/.carrier/chat/logs")
    #expect(command.logPath == "/h/.carrier/chat/logs/app-start.log")
    #expect(command.socketPath == "/h/.carrier/chat/state/chat.sock")
}

@Test func carrierHomeInTheEnvironmentMovesTheFolder() throws {
    let command = try #require(startChatHostCommand(settings: complete, carrier: homebrew, environment: ["CARRIER_HOME": "/scratch"], home: "/h"))
    #expect(command.environment["CARRIER_HOME"] == "/scratch")
    #expect(command.logPath == "/scratch/chat/logs/app-start.log")
    #expect(command.socketPath == "/scratch/chat/state/chat.sock")
}

@Test func withoutCarrierThereIsNoHostCommandAndOnlyItIsNamed() {
    #expect(startChatHostCommand(settings: complete, carrier: nil, environment: [:], home: "/h") == nil)
    #expect(startMissing(complete, carrier: nil) == ["carrier"])
}

@Test func aScriptWithoutNodeNeedsNodeButABinaryDoesNot() {
    #expect(startChatHostCommand(settings: SetupSettings(), carrier: "/work/main.ts", environment: [:], home: "/h") == nil)
    #expect(startMissing(SetupSettings(), carrier: "/work/main.js") == ["node"])
    #expect(startMissing(SetupSettings(), carrier: homebrew).isEmpty)
}

@Test func opening_startsTheHostOnlyWhenNothingAnswersOrRunsAndCarrierIsKnown() {
    func decide(answers: Bool = false, running: Bool = false, fixture: Bool = false, carrier: String? = homebrew) -> ChatHostAtOpen {
        chatHostAtOpen(settings: complete, carrier: carrier, hostAnswers: answers, startRunning: running, fixture: fixture)
    }
    #expect(decide() == .start)
    #expect(decide(answers: true) == .leave)
    #expect(decide(running: true) == .leave)
    #expect(decide(fixture: true) == .leave)
    #expect(decide(carrier: nil) == .missing(["carrier"]))
}

@Test func opening_saysNothingAboutWhatIsMissingWhenThereIsNothingToStart() {
    #expect(chatHostAtOpen(settings: complete, carrier: nil, hostAnswers: true, startRunning: false, fixture: false) == .leave)
    #expect(chatHostAtOpen(settings: complete, carrier: nil, hostAnswers: false, startRunning: false, fixture: true) == .leave)
}

@Test func theFailureTextNamesTheHost() {
    #expect(startFailureText(.exited(1), name: "The chat host").hasPrefix("The chat host exited with code 1"))
}
