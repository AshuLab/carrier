import Foundation
import Testing
@testable import CarrierCore

/// A client that answers what it was told to, and lets time pass by the amount a call takes.
private final class ScriptedClient: TextModelClient, @unchecked Sendable {
    var reply: Result<String, any Error>
    var asked: [(server: CleanupServer, model: String, system: String, text: String)] = []
    var takes: TimeInterval = 0
    let clock = Clock()

    final class Clock: @unchecked Sendable { var now = Date(timeIntervalSince1970: 1_000) }

    init(_ reply: Result<String, any Error>) { self.reply = reply }

    func models(of server: CleanupServer) async throws -> [String] { [] }

    func complete(server: CleanupServer, model: String, system: String, text: String, timeout: Duration) async throws -> String {
        asked.append((server, model, system, text))
        clock.now.addTimeInterval(takes)
        return try reply.get()
    }
}

private func run(_ client: ScriptedClient, server: CleanupServer? = .lmStudio, model: String? = "qwen", prompt: String = "Clean it") async throws -> CleanupResult {
    let clock = client.clock
    return try await CleanupRun(client: client, now: { clock.now }).run(server: server, model: model, prompt: prompt, text: "um hello")
}

private func failure(_ client: ScriptedClient, server: CleanupServer? = .lmStudio, model: String? = "qwen", prompt: String = "Clean it") async -> CleanupFailure? {
    do { _ = try await run(client, server: server, model: model, prompt: prompt); return nil } catch { return error as? CleanupFailure }
}

@Test func aCleanupGivesTheTrimmedTextAndHowLongTheModelTook() async throws {
    let client = ScriptedClient(.success("\n Hello.\n"))
    client.takes = 0.8
    let result = try await run(client)
    #expect(result.text == "Hello." && abs(result.seconds - 0.8) < 0.001)
    #expect(client.asked.count == 1)
    #expect(client.asked[0].server == .lmStudio && client.asked[0].model == "qwen" && client.asked[0].system == "Clean it" && client.asked[0].text == "um hello")
}

@Test func aServerThatIsDownIsSaidByName() async {
    #expect(await failure(ScriptedClient(.failure(CleanupFailure.serverDown(.ollama))), server: .ollama) == .serverDown(.ollama))
    #expect(CleanupFailure.serverDown(.ollama).message == "Ollama is not running")
}

@Test func aModelTheServerDoesNotHaveIsAFailureAndAnAbsentOneIsNeverAsked() async {
    #expect(await failure(ScriptedClient(.failure(CleanupFailure.noModel))) == .noModel)
    let client = ScriptedClient(.success("x"))
    #expect(await failure(client, model: nil) == .noModel)
    #expect(await failure(client, model: "") == .noModel)
    #expect(client.asked.isEmpty)
}

@Test func aTimeoutIsAFailure() async {
    #expect(await failure(ScriptedClient(.failure(CleanupFailure.timeout))) == .timeout)
}

@Test func anEmptyPromptOrNoServerAsksNothing() async {
    let client = ScriptedClient(.success("x"))
    #expect(await failure(client, prompt: "") == .emptyPrompt)
    #expect(await failure(client, prompt: " \n ") == .emptyPrompt)
    #expect(await failure(client, server: nil) == .noServer)
    #expect(client.asked.isEmpty)
}

@Test func aReplyWithNoTextOrAnErrorOfAnotherKindIsABadReply() async {
    #expect(await failure(ScriptedClient(.success("  \n"))) == .badReply("The model answered with no text"))
    struct Odd: LocalizedError { var errorDescription: String? { "odd" } }
    #expect(await failure(ScriptedClient(.failure(Odd()))) == .badReply("odd"))
}

@Test func cleanupCanBeOnOnlyWithAServerAndAModel() {
    #expect(cleanupCanBeOn(server: .ollama, model: "llama3.2:3b"))
    #expect(cleanupCanBeOn(server: nil, model: "llama3.2:3b") == false)
    #expect(cleanupCanBeOn(server: .ollama, model: nil) == false)
    #expect(cleanupCanBeOn(server: .ollama, model: "") == false)
}

@Test func theDefaultPromptKeepsTheLanguageThatWasSpoken() {
    #expect(defaultCleanupPrompt.contains("filler words") && defaultCleanupPrompt.contains("keep the language that was spoken"))
}
