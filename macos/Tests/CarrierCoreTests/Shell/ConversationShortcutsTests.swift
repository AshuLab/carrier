import Foundation
import Testing
@testable import CarrierCore

// The shortcuts of the Conversation group: the fold toggle, the last answer, and that they do nothing without an open conversation.

private func table() -> ShortcutTable {
    let suite = "conversation-shortcuts-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return ShortcutTable(defaults: defaults)
}

/// A feed of two runs of calls, the second one failed.
private func feed(secondFails: Bool = true) -> [FeedRow] {
    chatFeed([
        ChatEvent(id: 1, at: 1, kind: "tool_start", callId: "a", tool: "Read", arg: "a.ts"),
        ChatEvent(id: 2, at: 2, kind: "tool_end", callId: "a", status: "ok"),
        ChatEvent(id: 3, at: 3, kind: "assistant", text: "first"),
        ChatEvent(id: 4, at: 4, kind: "tool_start", callId: "b", tool: "Bash", arg: "ls"),
        ChatEvent(id: 5, at: 5, kind: "tool_end", callId: "b", status: secondFails ? "err" : "ok"),
    ], bundle: english.bundle, locale: english.locale)
}

private func groupIds(_ rows: [FeedRow]) -> [String] { rows.compactMap { if case .tools(let id, _) = $0 { id } else { nil } } }

private func openGroups(_ rows: [FeedRow], flipped: Set<String>) -> [Bool] {
    rows.compactMap { row in
        guard case .tools(let id, let group) = row else { return nil }
        _ = group
        return flipped.contains(id)
    }
}

@Test func theDefaultsAreTheSpecsCombinations() {
    let table = table()
    #expect(shortcutAction(key: "l", modifiers: .command, in: table) == .conversation(.focusBox))
    #expect(shortcutAction(key: ".", modifiers: .command, in: table) == .conversation(.stopAgent))
    #expect(shortcutAction(key: "\u{F701}", modifiers: .command, in: table) == .conversation(.jumpToLatest))
    #expect(shortcutAction(key: "e", modifiers: [.command, .option], in: table) == .conversation(.toggleToolFolds))
    #expect(shortcutAction(key: "c", modifiers: [.command, .shift], in: table) == .conversation(.copyLastAnswer))
    #expect(ShortcutCommand.latestMessage.defaultCombo?.text == "⌘↓")
    #expect(ShortcutCommand.foldTools.defaultCombo?.text == "⌥⌘E")
}

@Test func everyRunIsFoldedUntilItIsFlipped() {
    #expect(openGroups(feed(), flipped: []) == [false, false])
}

@Test func foldingUnfoldsAllWhenAllAreFoldedAndFoldsAllWhenAnyIsOpen() {
    let rows = feed()
    let ids = groupIds(rows)
    let unfolded = togglingToolGroups(in: rows, flipped: [])
    #expect(unfolded == Set(ids) && openGroups(rows, flipped: unfolded) == [true, true])
    // one open and one folded: everything folds
    #expect(openGroups(rows, flipped: togglingToolGroups(in: rows, flipped: Set(ids.prefix(1)))) == [false, false])
    #expect(togglingToolGroups(in: rows, flipped: unfolded).isEmpty)
}

@Test func foldingAConversationWithoutRunsChangesNothing() {
    let rows: [FeedRow] = [.user(id: "u", text: "hi")]
    #expect(togglingToolGroups(in: rows, flipped: ["x"]) == ["x"])
}

// A row is drawn again when its own keys of `flipped` change, and not when a key of another row does.
@Test func aRowTakesFromFlippedItsOwnKeyAndTheOnesUnderIt() {
    let flipped: Set<String> = ["e5", "e5/e6", "e5/earlier", "e50", "e50/e6", "e55/e6", "e4", "x/e5"]
    #expect(flippedKeys(of: "e5", in: flipped) == ["e5", "e5/e6", "e5/earlier"])
    #expect(flippedKeys(of: "e50", in: flipped) == ["e50", "e50/e6"])
    #expect(flippedKeys(of: "e7", in: flipped).isEmpty)
    #expect(flippedKeys(of: "e5", in: []).isEmpty)
}

@Test func theLastAnswerIsTheTextOfTheLastAgentMessage() {
    #expect(lastAnswer(in: feed()) == "first")
    let rows = feed() + [.user(id: "u", text: "more"), .agent(id: "a2", text: "second", inProgress: false), .turnEnd(id: "t", TurnSummary(duration: "12s"))]
    #expect(lastAnswer(in: rows) == "second")
}

@Test func thereIsNoLastAnswerBeforeTheAgentWrote() {
    #expect(lastAnswer(in: []) == nil)
    #expect(lastAnswer(in: [.user(id: "u", text: "hi"), .tools(id: "t", ToolGroup(calls: []))]) == nil)
}

@Test func theConversationActionsAreRequestsOfTheOpenConversation() {
    let shell = WindowShell()
    shell.selection = .session(id: "s1")
    shell.perform(.conversation(.focusBox))
    #expect(shell.conversationRequest == ConversationRequest(action: .focusBox, count: 1))
    shell.perform(.conversation(.focusBox))
    #expect(shell.conversationRequest?.count == 2)
}

@Test func theConversationActionsDoNothingWithoutAnOpenConversation() {
    let shell = WindowShell()
    for selection in [Selection.home, .sessions, .archive, .carrier, .epic(repo: "acme/web", issue: 7)] {
        shell.selection = selection
        for action in [ConversationAction.focusBox, .stopAgent, .jumpToLatest, .toggleToolFolds, .copyLastAnswer, .dictate] { shell.perform(.conversation(action)) }
        #expect(shell.conversationRequest == nil)
    }
}

@Test func theDraftOfANewSessionTakesOnlyTheActionsThatAreAboutItsBox() {
    let shell = WindowShell()
    shell.selection = .newSession
    for action in [ConversationAction.stopAgent, .jumpToLatest, .toggleToolFolds, .copyLastAnswer, .stopSubagent, .stopProcess("p1"), .stopProcesses] { shell.perform(.conversation(action)) }
    #expect(shell.conversationRequest == nil)
    shell.perform(.conversation(.dictate))
    #expect(shell.conversationRequest == ConversationRequest(action: .dictate, count: 1))
    shell.perform(.conversation(.focusBox))
    #expect(shell.conversationRequest == ConversationRequest(action: .focusBox, count: 2))
}

@Test func theProcessesStopsAreRequestsOfTheOpenConversationAndTheProcessesGoWithTheSession() {
    let shell = WindowShell()
    shell.selection = .session(id: "s1")
    shell.processes = ProcessesCard([BackgroundTask(id: "p1", kind: "local_bash", description: "pnpm dev", agentWork: false)], canStop: true)
    shell.perform(.conversation(.stopProcess("p1")))
    #expect(shell.conversationRequest == ConversationRequest(action: .stopProcess("p1"), count: 1))
    shell.perform(.conversation(.stopProcesses))
    #expect(shell.conversationRequest == ConversationRequest(action: .stopProcesses, count: 2))
    // choosing the open session again leaves them: its conversation is not made anew and would not push them again
    shell.selection = .session(id: "s1")
    #expect(shell.processes != nil)
    shell.selection = .session(id: "s2")
    #expect(shell.processes == nil)
}
