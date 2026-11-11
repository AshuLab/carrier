import Foundation
import Testing
@testable import CarrierCore

// The rows of the Providers page: the host's `providers` reply joined with who uses each account in config.json and chat.json.

private let golden = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/chat-providers.json")

private func reply(_ json: String? = nil) throws -> HostProviders {
    try JSONDecoder().decode(HostProviders.self, from: json.map { Data($0.utf8) } ?? Data(contentsOf: golden))
}

private func data(_ json: String) -> Data { Data(json.utf8) }

private let config = data("""
{
  "agents": { "author": { "provider": "claude" }, "reviewer": { "provider": "codex" } },
  "repos": [
    { "name": "acme/web", "agents": { "reviewer": { "provider": "claude-work" } } },
    { "name": "acme/api" }
  ],
  "failover": { "roles": { "author": [{ "provider": "claude-work" }] } }
}
""")

@Test func anAccountUsedByARoleSaysWhichOne() throws {
    let uses = accountUses(config: config, chat: data(#"{"agents":{}}"#))
    #expect(uses["codex"] == [.role(.reviewer)])
    #expect(uses["claude"]?.first == .role(.author))
    #expect(AccountUse.role(.leadReviewer).text == "Lead reviewer")
}

@Test func anAccountUsedByARepoOverrideNamesTheRepoAndTheRole() {
    #expect(accountUses(config: config, chat: data(#"{"agents":{}}"#))["claude-work"]?.first == .repoOverride(repo: "acme/web", role: .reviewer))
    #expect(AccountUse.repoOverride(repo: "acme/web", role: .reviewer).text == "Reviewer in acme/web")
}

@Test func anAccountInARolesFailoverStepsIsUsedByThatRole() {
    let uses = accountUses(config: config, chat: data(#"{"agents":{}}"#))
    #expect(uses["claude"] == [.role(.author)])
    #expect(uses["claude-work"] == [.repoOverride(repo: "acme/web", role: .reviewer), .failover(.author)])
}

@Test func anAccountUsedByAChatAgentNamesTheAgent() {
    let chat = data(#"{"agents":{"work":{"account":"claude-work"},"main":{"account":"claude"}}}"#)
    let uses = accountUses(config: nil, chat: chat)
    #expect(uses["claude-work"] == [.chatAgent("work")] && uses["claude"] == [.chatAgent("main")])
    #expect(uses["codex"] == nil)
    #expect(AccountUse.chatAgent("work").text == "Chat agent work")
}

@Test func withoutChatJsonTheChatsDefaultAgentsUseTheAccountsOfTheirName() {
    let uses = accountUses(config: nil, chat: nil)
    #expect(uses["claude"] == [.chatAgent("claude")] && uses["codex"] == [.chatAgent("codex")])
}

@Test func anAccountNobodyNamesIsNotUsedAndFilesThatDoNotReadNameNobody() throws {
    let page = providersPage(try reply(), config: config, chat: data(#"{"agents":{}}"#))
    let work = try #require(page.tools[0].accounts.first { $0.name == "claude-work" })
    let unused = providersPage(try reply(), config: data(#"{"agents":{}}"#), chat: data(#"{"agents":{}}"#))
    #expect(unused.tools[0].accounts.allSatisfy { $0.uses.isEmpty && $0.usedBy == "Not used yet" })
    #expect(work.usedBy == "Used by Reviewer in acme/web, Failover of Author")
    let broken = providersPage(try reply(), config: data("not json"), chat: data("[1]"))
    #expect(broken.tools[0].accounts.allSatisfy { $0.uses.isEmpty || $0.uses == [.chatAgent("claude")] })
}

@Test func theGoldenReplyBecomesToolsWithStateVersionAndPath() throws {
    let page = providersPage(try reply(), config: nil, chat: nil)
    #expect(page.tools.map(\.id) == ["claude", "codex", "agy"])
    let claude = page.tools[0]
    #expect(claude.title == "Claude Code" && claude.status == .ready && claude.status.text == "Signed in")
    #expect(claude.version == "2.1.3 (Claude Code)" && claude.path == "/opt/homebrew/bin/claude")
    #expect(claude.accounts.map(\.title) == ["claude", "Work"])
    #expect(claude.accounts.map(\.state) == [.ready, .signedOut])
    #expect(claude.accounts[1].configDir == "/Users/demo/.claude-work")
    // codex answers no version, and its state is a probe that did not answer
    #expect(page.tools[1].status == .unknown && page.tools[1].version == nil && page.tools[1].path == "/opt/homebrew/bin/codex")
    // the account's own binary reaches Sign in and Update
    #expect(claude.command == nil && claude.accounts[1].command == nil)
    #expect(page.tools[1].command == "/opt/homebrew/bin/codex" && page.tools[1].accounts[0].command == "/opt/homebrew/bin/codex")
}

@Test func aHarnessFoundWithNoAccountIsFoundNotAdded() throws {
    let agy = try #require(providersPage(try reply(), config: nil, chat: nil).tools.last)
    #expect(agy.id == "agy" && agy.status == .foundNotAdded && agy.accounts.isEmpty)
    #expect(agy.version == "1.4.0" && agy.path == "/Users/demo/.local/bin/agy")
}

@Test func aToolWithNothingIsNotInstalledAndAToolOfOnlySignedOutAccountsIsSignedOut() throws {
    let none = try reply(#"{"accounts":[{"name":"claude","harness":"claude","found":false,"state":"missing"}],"unadded":[],"servers":[]}"#)
    let page = providersPage(none, config: nil, chat: nil)
    #expect(page.tools.map(\.status) == [.missing, .missing, .missing])
    let out = try reply(#"{"accounts":[{"name":"claude","harness":"claude","found":true,"path":"/bin/claude","state":"signedOut"}],"unadded":[],"servers":[]}"#)
    #expect(providersPage(out, config: nil, chat: nil).tools[0].status == .signedOut)
}

@Test func theLocalServersShowTheirModelsOrThatTheyAreNotRunning() throws {
    let servers = providersPage(try reply(), config: nil, chat: nil).servers
    #expect(servers.map(\.title) == ["LM Studio", "Ollama"])
    #expect(servers[0].running == false && servers[0].status == "Not running" && servers[0].models.isEmpty)
    #expect(servers[1].status == "Running · 2 models" && servers[1].models == ["qwen3:8b", "llama3.2:3b"])
    // a server the host did not list is not running
    let bare = providersPage(try reply(#"{"accounts":[],"unadded":[],"servers":[]}"#), config: nil, chat: nil)
    #expect(bare.servers.allSatisfy { $0.running == false })
}

@Test func withoutAReplyThePageSaysWhyInWordsAndAProblemFileSaysWhichKey() throws {
    #expect(ProvidersOutcome.noHost.note?.contains("not running") == true)
    #expect(ProvidersOutcome.tooOld.note?.contains("too old") == true)
    #expect(ProvidersOutcome.failed("The chat host is not answering").note == "The chat host could not list the AI tools: The chat host is not answering")
    #expect(ProvidersOutcome.unasked.note?.isEmpty == false)
    let problem = try reply(#"{"accounts":[],"unadded":[],"servers":[],"problem":{"path":"/h/providers.json","message":"providers.claude.harness: Invalid option"}}"#)
    #expect(ProvidersOutcome.reply(problem).note?.contains("providers.claude.harness: Invalid option") == true)
    #expect(ProvidersOutcome.reply(try reply()).note == nil)
}
