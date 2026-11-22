@testable import CarrierCore
import SwiftUI
import Testing
@testable import Carrier

// A row of the feed is drawn again only when something it draws changed: SwiftUI skips a row that is `==` to the one it has. While the agent
// writes, the feed is made again at each poll, and every row of it that is `==` is left alone.

@MainActor private func row(
    _ row: FeedRow = .agent(id: "e2", text: "Hello", inProgress: false), time: Int? = 1_000, summary: TurnSummary? = nil, pinned: Bool = false,
    flipped: Set<String> = [], agent: String = "claude", commands: [ChatCommand] = [], offersWayOut: Bool = false,
    work: WorkState = WorkState(live: false, waiting: false, since: nil)
) -> FeedRowView {
    FeedRowView(row: row, time: time, summary: summary, pinned: pinned, flipped: .constant(flipped), agent: agent, commands: commands, offersWayOut: offersWayOut, work: work)
}

@MainActor @Test func aRowMadeAgainFromTheSameInputsIsTheSameRow() {
    let summary = TurnSummary(duration: "12s")
    let command = ChatCommand(id: "s:review", name: "review", description: "")
    #expect(row(summary: summary, flipped: ["e2/x"], commands: [command]) == row(summary: summary, flipped: ["e2/x"], commands: [command]))
}

@MainActor @Test func aRowIsDrawnAgainWhenAnythingItDrawsChanges() {
    let command = ChatCommand(id: "s:review", name: "review", description: "")
    let base = row()
    #expect(base != row(.agent(id: "e2", text: "Hello again", inProgress: false)))
    #expect(base != row(.agent(id: "e2", text: "Hello", inProgress: true)))
    #expect(base != row(time: 2_000))
    #expect(base != row(summary: TurnSummary(duration: "12s")))
    #expect(base != row(pinned: true))
    #expect(base != row(agent: "codex"))
    #expect(base != row(commands: [command]))
    #expect(base != row(offersWayOut: true))
    #expect(base != row(work: WorkState(live: true, waiting: false, since: nil)))
    #expect(base != row(work: WorkState(live: false, waiting: true, since: nil)))
    #expect(base != row(work: WorkState(live: false, waiting: false, since: 5)))
}

@MainActor @Test func aRowIsDrawnAgainForItsOwnFlippedKeysAndNotForAnotherRows() {
    let run = FeedRow.tools(id: "e5", ToolGroup(calls: []))
    let base = row(run)
    #expect(base != row(run, flipped: ["e5"]))
    #expect(base != row(run, flipped: ["e5/e6"]))
    #expect(base == row(run, flipped: ["e50", "e50/e6", "e4"]))
    #expect(row(run, flipped: ["e5", "e9"]) == row(run, flipped: ["e5"]))
}

// The actions are the same value at every pass of the conversation, so a row that reads them is not invalidated for them: two are the same
// when they hold the same model. A closure made at each pass would be another one every time.
@MainActor @Test func theActionsOfTwoPassesOfTheSameConversationAreEqual() {
    let model = ConversationModel(host: SocketChatHost(), sessionId: "s1")
    #expect(FeedActions(model: model) == FeedActions(model: model))
    #expect(FeedActions(model: model) != FeedActions(model: ConversationModel(host: SocketChatHost(), sessionId: "s2")))
    #expect(FeedActions(model: nil) == FeedActions(model: nil))
    #expect(EnvironmentValues().feedActions == FeedActions(model: nil))
}

// A new stored property of the row has to be placed in one of the two lists below: in `compared` once `==` reads it (and the test above that
// changes it), or in `notCompared` with the reason it does not need to. A property that is in neither makes this test fail, so it cannot be forgotten.
@MainActor @Test func everyStoredPropertyOfARowIsComparedOrDeliberatelyLeftOut() {
    let compared: Set<String> = ["row", "time", "summary", "pinned", "flippedHere", "agent", "commands", "offersWayOut", "work"]
    // `flipped` is only written to, `flippedHere` is what is compared; the environment, the defaults and the states invalidate the row by themselves
    let notCompared: Set<String> = ["flipped", "actions", "messageTimes", "hovering", "copied", "overCopy"]
    // a property wrapper shows as `_name` (`__name` for a `@State`), so the underscores are dropped
    let stored = Set(Mirror(reflecting: row()).children.compactMap { $0.label?.drop(while: { $0 == "_" }).description })
    #expect(stored == compared.union(notCompared))
}
