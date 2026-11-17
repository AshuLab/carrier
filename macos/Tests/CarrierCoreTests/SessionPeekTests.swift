import Foundation
import Testing
@testable import CarrierCore

@Test func aSessionsPeekHasItsWholeTitleItsLastMessageAndWhereItWorks() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let row = SessionRow(
        id: "s1", title: "A title that the row would cut", workspace: "carrier", agent: "claude", state: .idle,
        updatedAt: now.addingTimeInterval(-7200), branch: "carrier/void-corsair-pylon", folder: "/srv/wt/void-corsair-pylon",
        lastMessage: "Done: the pill has room now.", turns: 3, reportsActivity: true
    )
    let card = sessionPeek(row, now: now)
    #expect(card.title == "A title that the row would cut" && card.name == "carrier" && card.subtitle == "Idle")
    #expect(card.lastMessage == "Done: the pill has room now.")
    #expect(card.facts.map(\.label) == ["Where", "Folder", "Agent", "Turns"])
    #expect(card.facts.map(\.value) == ["Worktree · carrier/void-corsair-pylon", "/srv/wt/void-corsair-pylon", "claude", "3"])
    #expect(card.timeline == "updated 2 hours ago")
}

@Test func aSessionInThePlainFolderSaysBaseFolderAndOneWaitingForYouSaysSo() {
    let row = SessionRow(id: "s2", title: "t", workspace: "web", agent: "", state: .waiting, updatedAt: Date(), folder: "")
    let card = sessionPeek(row, now: Date())
    #expect(card.subtitle == "Waiting for you" && card.lastMessage == nil)
    #expect(card.facts == [.init(label: "Where", value: "Base folder")])
}

@Test func aPeekTintsTheStateAsTheRowDoesAndSaysItsPullRequestItsLinesAndWhatItWaitsFor() {
    func peek(_ state: SessionState, unread: Bool = false, background: [BackgroundTask] = []) -> SessionPeek {
        sessionPeek(SessionRow(id: "s", title: "t", workspace: "w", agent: "claude", state: state, updatedAt: Date(), unread: unread, background: background), now: Date())
    }
    #expect(peek(.working).tone == .working && peek(.waiting).tone == .waiting && peek(.idle).tone == .quiet)
    let done = peek(.idle, unread: true)
    #expect(done.subtitle == "Done" && done.tone == .done)
    let task = BackgroundTask(id: "b", kind: "local_bash", description: "pnpm build")
    let waiting = peek(.idle, unread: true, background: [task])
    #expect(waiting.subtitle == "Waiting on background work…" && waiting.tone == .background && waiting.background == [task])

    var row = SessionRow(id: "s", title: "t", workspace: "w", agent: "", state: .idle, updatedAt: Date(), branch: "fix/x", folder: "/srv/wt")
    row.pullRequest = SessionPullRequest(number: 9, url: "https://github.com/o/r/pull/9", state: .draft)
    row.diff = SessionDiff(added: 5, removed: 2)
    let card = sessionPeek(row, now: Date())
    #expect(card.pullRequest?.number == 9 && card.diff == SessionDiff(added: 5, removed: 2))
    // a branch and a path are set in monospace
    #expect(card.facts.map(\.monospaced) == [true, true])
    // the card shows the lines changed even for a session with no pull request, which its row does not
    row.pullRequest = nil
    #expect(sessionPeek(row, now: Date()).diff != nil && sessionPeek(row, now: Date()).pullRequest == nil)
    #expect(sessionPeek(SessionRow(id: "s", title: "t", workspace: "w", agent: "", state: .idle, updatedAt: Date()), now: Date()).facts.map(\.monospaced) == [false])
}
