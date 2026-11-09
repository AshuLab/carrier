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
    ])
}

private func groupIds(_ rows: [FeedRow]) -> [String] { rows.compactMap { if case .tools(let id, _) = $0 { id } else { nil } } }

private func openGroups(_ rows: [FeedRow], flipped: Set<String>) -> [Bool] {
    rows.compactMap { row in
        guard case .tools(let id, let group) = row else { return nil }
        return group.opensByDefault(.collapsed, opensFailed: true) != flipped.contains(id)
    }
}

@Test func theDefaultsAreTheSpecsCombinations() {
    let table = table()
    #expect(shortcutAction(key: "l", modifiers: .command, in: table) == .conversation(.focusBox))
    #expect(shortcutAction(key: "\u{F701}", modifiers: .command, in: table) == .conversation(.jumpToLatest))
    #expect(shortcutAction(key: "e", modifiers: [.command, .option], in: table) == .conversation(.toggleToolFolds))
    #expect(shortcutAction(key: "c", modifiers: [.command, .shift], in: table) == .conversation(.copyLastAnswer))
    #expect(ShortcutCommand.latestMessage.defaultCombo?.text == "⌘↓")
    #expect(ShortcutCommand.foldTools.defaultCombo?.text == "⌥⌘E")
}

@Test func foldingFoldsEveryRunWhenTheyAreMixed() {
    let rows = feed()
    // the failed run opens by itself, the other is folded
    #expect(openGroups(rows, flipped: []) == [false, true])
    let next = togglingToolGroups(in: rows, mode: .collapsed, opensFailed: true, flipped: [])
    #expect(openGroups(rows, flipped: next) == [false, false])
}

@Test func foldingFoldsAllWhenAllAreOpenAndUnfoldsAllWhenAllAreFolded() {
    let rows = feed()
    let ids = groupIds(rows)
    let allOpen = Set(ids.prefix(1))
    #expect(openGroups(rows, flipped: allOpen) == [true, true])
    #expect(openGroups(rows, flipped: togglingToolGroups(in: rows, mode: .collapsed, opensFailed: true, flipped: allOpen)) == [false, false])
    let folded = togglingToolGroups(in: rows, mode: .collapsed, opensFailed: true, flipped: [])
    #expect(openGroups(rows, flipped: togglingToolGroups(in: rows, mode: .collapsed, opensFailed: true, flipped: folded)) == [true, true])
}

@Test func foldingFollowsTheDefaultOfTheMode() {
    let rows = feed(secondFails: false)
    // expanded: all open by default, so the first press folds them, the second unfolds
    let folded = togglingToolGroups(in: rows, mode: .expanded, opensFailed: true, flipped: [])
    #expect(folded == Set(groupIds(rows)))
    #expect(togglingToolGroups(in: rows, mode: .expanded, opensFailed: true, flipped: folded).isEmpty)
}

@Test func foldingAConversationWithoutRunsChangesNothing() {
    let rows: [FeedRow] = [.user(id: "u", text: "hi")]
    #expect(togglingToolGroups(in: rows, mode: .collapsed, opensFailed: true, flipped: ["x"]) == ["x"])
}

@Test func theLastAnswerIsTheTextOfTheLastAgentMessage() {
    #expect(lastAnswer(in: feed()) == "first")
    let rows = feed() + [.user(id: "u", text: "more"), .agent(id: "a2", text: "second", inProgress: false), .turnEnd(id: "t", text: "12s")]
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
    for selection in [Selection.home, .sessions, .newSession, .archive, .carrier, .epic(repo: "acme/web", issue: 7)] {
        shell.selection = selection
        for action in [ConversationAction.focusBox, .jumpToLatest, .toggleToolFolds, .copyLastAnswer] { shell.perform(.conversation(action)) }
        #expect(shell.conversationRequest == nil)
    }
}
