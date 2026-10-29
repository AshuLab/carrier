import Foundation
import Testing

@testable import CarrierCore

private let commands = [
    ChatCommand(id: "compact", name: "compact", description: "Free up context", kind: .command),
    ChatCommand(id: "review", name: "review", description: "Review a change", argumentHint: "<pr>"),
    ChatCommand(id: "pdf", name: "pdf", description: "Read and write PDFs"),
    ChatCommand(id: "superset:review-helper", name: "review-helper", description: "Helps a review"),
]

@Test func theNameBeingTypedIsTheWordUnderTheCaretThatStartsWithASlash() {
    #expect(commandToken(in: "/", cursor: 1) == CommandToken(range: NSRange(location: 0, length: 1), query: ""))
    #expect(commandToken(in: "/rev", cursor: 4)?.query == "rev")
    // anywhere in the text, after a space or a line
    #expect(commandToken(in: "please /rev", cursor: 11) == CommandToken(range: NSRange(location: 7, length: 4), query: "rev"))
    #expect(commandToken(in: "a\n/rev", cursor: 6)?.query == "rev")
    // the caret in the middle: what is before it is the query, the whole word is what is replaced
    #expect(commandToken(in: "/review now", cursor: 4) == CommandToken(range: NSRange(location: 0, length: 7), query: "rev"))
    // a space ends it, a path or a word is not one, the caret before the slash is not in it
    #expect(commandToken(in: "/review 42", cursor: 10) == nil)
    #expect(commandToken(in: "src/chat", cursor: 8) == nil)
    #expect(commandToken(in: "/usr/bin", cursor: 8) == nil)
    #expect(commandToken(in: "review", cursor: 6) == nil)
    #expect(commandToken(in: "x /rev", cursor: 2) == nil)
    #expect(commandToken(in: "", cursor: 0) == nil)
}

@Test func aChosenCommandTakesTheWordAndLeavesTheCaretAfterOneSpace() throws {
    let review = commands[1]
    var token = try #require(commandToken(in: "please /re now", cursor: 10))
    #expect(inserting(review, over: token, in: "please /re now") == ("please /review now", 15))
    token = try #require(commandToken(in: "/re", cursor: 3))
    #expect(inserting(review, over: token, in: "/re") == ("/review ", 8))
    #expect(inserting(review, over: try #require(commandToken(in: "/", cursor: 1)), in: "/") == ("/review ", 8))
}

@Test func theSlashButtonAppendsASlashAfterASpace() {
    #expect(appendingSlash(to: "") == ("/", 1))
    #expect(appendingSlash(to: "hello") == ("hello /", 7))
    #expect(appendingSlash(to: "hello ") == ("hello /", 7))
    #expect(appendingSlash(to: "hello\n") == ("hello\n/", 7))
}

@Test func aPluginsSkillSplitsIntoItsPluginAndItsName() {
    let skill = ChatCommand(id: "x", name: "solve:code-post", description: "")
    #expect(skill.source == "solve" && skill.shortName == "code-post")
    #expect(commands[1].source == nil && commands[1].shortName == "review")
    // the description loses the plugin the name already says, and only that one
    #expect(ChatCommand(id: "x", name: "solve:land", description: "(solve) Merge it").summary == "Merge it")
    #expect(ChatCommand(id: "x", name: "solve:land", description: "(other) Merge it").summary == "(other) Merge it")
    #expect(ChatCommand(id: "x", name: "land", description: "(solve) Merge it").summary == "(solve) Merge it")
}

@Test func theMatchesAreSkillsFirstAndNamesThatStartWithItBeforeThoseThatContainIt() {
    #expect(commandMatches(commands, query: "").map(\.name) == ["review", "pdf", "review-helper", "compact"])
    #expect(commandMatches(commands, query: "rev").map(\.name) == ["review", "review-helper"])
    #expect(commandMatches(commands, query: "view").map(\.name) == ["review", "review-helper"])
    #expect(commandMatches(commands, query: "context").map(\.name) == ["compact"])  // by its description
    #expect(commandMatches(commands, query: "zzz").isEmpty)
    #expect(commandMatches(commands, query: "REV").map(\.name) == ["review", "review-helper"])
}

@Test func aMessageInvokesACommandWhenItStartsWithItsExactNameAndTheRestIsItsArguments() {
    let invoked = invokedCommand(in: "  /review  the diff of 42\n", among: commands)
    #expect(invoked?.command.id == "review" && invoked?.arguments == "the diff of 42")
    #expect(invokedCommand(in: "/review", among: commands)?.arguments == "")
    #expect(invokedCommand(in: "/review-helper x", among: commands)?.command.id == "superset:review-helper")
    // part of a name, another name, no slash, a slash in the middle
    #expect(invokedCommand(in: "/rev x", among: commands) == nil)
    #expect(invokedCommand(in: "/nope", among: commands) == nil)
    #expect(invokedCommand(in: "review x", among: commands) == nil)
    #expect(invokedCommand(in: "please /review", among: commands) == nil)
}

@Test func theEventsReplyCarriesTheCommandsAndAnOldHostSaysNone() throws {
    let json = #"{"events":[],"cursor":0,"streaming":"","commands":[{"id":"review","name":"review","description":"Review","argumentHint":"<pr>","kind":"skill"}]}"#
    let reply = try JSONDecoder().decode(ChatEvents.self, from: Data(json.utf8))
    #expect(reply.commands == [ChatCommand(id: "review", name: "review", description: "Review", argumentHint: "<pr>")])
    #expect(try JSONDecoder().decode(ChatEvents.self, from: Data(#"{"events":[],"cursor":0,"streaming":""}"#.utf8)).commands.isEmpty)
}

@Test func aCommandIsAWordOnceASpaceFollowsItOrTheMessageIsSent() {
    let typing = commandSpans(in: "ask /review and /pdf", among: commands)
    #expect(typing.map(\.range) == [NSRange(location: 4, length: 7)] && typing.map(\.command.name) == ["review"])
    let sent = commandSpans(in: "ask /review and /pdf", among: commands, ended: true)
    #expect(sent.map(\.command.name) == ["review", "pdf"] && sent[1].range == NSRange(location: 16, length: 4))
    // a path, a name that is not listed and a name that is only part of one are not commands
    #expect(commandSpans(in: "src/review /nope /rev x", among: commands, ended: true).isEmpty)
}
