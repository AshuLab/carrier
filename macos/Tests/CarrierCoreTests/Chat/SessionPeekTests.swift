import Foundation
import Testing
@testable import CarrierCore

@Test func aSessionsPeekHasItsWholeTitleItsLastMessageAndWhereItWorks() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let row = SessionRow(
        id: "s1", title: "A title that the row would cut", workspace: "carrier", agent: "claude", state: .idle,
        updatedAt: now.addingTimeInterval(-7200), branch: "carrier/void-corsair-pylon", branchFrom: "origin/main", folder: "/srv/wt/void-corsair-pylon",
        lastMessage: "Done: the pill has room now.", turns: 3, reportsActivity: true
    )
    let card = sessionPeek(row, now: now, bundle: english.bundle, locale: english.locale)
    #expect(card.title == "A title that the row would cut" && card.name == "carrier" && card.subtitle == "Idle")
    #expect(card.lastMessage == "Done: the pill has room now.")
    #expect(card.facts.map(\.label) == ["Where", "Branch", "Folder", "Agent", "Turns"])
    // a worktree says whose it is, the branch it was cut from, and its folder by name with the whole path under it
    #expect(card.facts.map(\.value) == ["Worktree of carrier", "carrier/void-corsair-pylon", "void-corsair-pylon", "claude", "3"])
    #expect(card.facts.map(\.detail) == [nil, "cut from origin/main", "/srv/wt/void-corsair-pylon", nil, nil])
    // a long branch or folder is drawn on one line and an agent as its account, so each fact says what it is
    #expect(card.facts.map(\.kind) == [.text, .branch, .path, .agent, .text])
    #expect(card.timeline == "updated 2 hours ago")
}

@Test func aSessionInThePlainFolderSaysBaseFolderAndOneWaitingForYouSaysSo() {
    let row = SessionRow(id: "s2", title: "t", workspace: "web", agent: "", state: .waiting, updatedAt: Date(), folder: "")
    let card = sessionPeek(row, now: Date(), bundle: english.bundle, locale: english.locale)
    #expect(card.subtitle == "Waiting for you" && card.tone == .attention && card.lastMessage == nil)
    #expect(card.facts == [.init(label: "Where", value: "Base folder")])
}

@Test func theStateOfASessionIsSaidInTheWordsAndColourOfItsRow() {
    func peek(_ state: SessionState, unread: Bool = false) -> SessionPeek {
        sessionPeek(SessionRow(id: "s", title: "t", workspace: "w", agent: "", state: state, updatedAt: Date(), unread: unread), now: Date(), bundle: english.bundle, locale: english.locale)
    }
    #expect(peek(.working).subtitle == "Working…" && peek(.working).tone == .working)
    #expect(peek(.idle).subtitle == "Idle" && peek(.idle).tone == .quiet)
    // the row says Done for a turn that ended and has not been opened, so the card does too
    #expect(peek(.idle, unread: true).subtitle == "Done" && peek(.idle, unread: true).tone == .done)
    #expect(peek(.done, unread: true).subtitle == "Done" && peek(.done).subtitle == "Idle")
    // a session the host put to sleep says so; a turn that ended unread outranks it, as it does for the row
    func asleep(unread: Bool) -> SessionPeek {
        sessionPeek(SessionRow(id: "s", title: "t", workspace: "w", agent: "", state: .idle, updatedAt: Date(), asleep: true, unread: unread), now: Date(), bundle: english.bundle, locale: english.locale)
    }
    #expect(asleep(unread: false).subtitle == "Asleep" && asleep(unread: false).tone == .quiet)
    #expect(asleep(unread: true).subtitle == "Done")
    // waiting and working outrank unread: the person is needed, or the agent is at work, whatever was or was not opened
    #expect(peek(.waiting, unread: true).subtitle == "Waiting for you" && peek(.waiting, unread: true).tone == .attention)
    #expect(peek(.working, unread: true).subtitle == "Working…" && peek(.working, unread: true).tone == .working)
    // a turn that ended with the agent still waiting for what it started is cyan, and not done or asleep
    #expect(sessionPeek(SessionRow(id: "s", title: "t", workspace: "w", agent: "", state: .idle, updatedAt: Date(), asleep: true, background: [BackgroundTask(id: "b", kind: "local_bash", description: "x")]), now: Date(), bundle: english.bundle, locale: english.locale).tone == .background)
}

@Test func aPeekTintsTheStateAsTheRowDoesAndSaysItsPullRequestItsLinesAndWhatItWaitsFor() {
    func peek(_ state: SessionState, unread: Bool = false, background: [BackgroundTask] = []) -> SessionPeek {
        sessionPeek(SessionRow(id: "s", title: "t", workspace: "w", agent: "claude", state: state, updatedAt: Date(), unread: unread, background: background), now: Date(), bundle: english.bundle, locale: english.locale)
    }
    #expect(peek(.working).tone == .working && peek(.waiting).tone == .attention && peek(.idle).tone == .quiet)
    let done = peek(.idle, unread: true)
    #expect(done.subtitle == "Done" && done.tone == .done)
    let task = BackgroundTask(id: "b", kind: "local_bash", description: "pnpm build")
    let waiting = peek(.idle, unread: true, background: [task])
    #expect(waiting.subtitle == "Waiting on background work…" && waiting.tone == .background && waiting.background == [task])

    var row = SessionRow(id: "s", title: "t", workspace: "w", agent: "", state: .idle, updatedAt: Date(), branch: "fix/x", folder: "/srv/wt")
    row.pullRequest = SessionPullRequest(number: 9, url: "https://github.com/o/r/pull/9", state: .draft)
    row.diff = SessionDiff(added: 5, removed: 2)
    let card = sessionPeek(row, now: Date(), bundle: english.bundle, locale: english.locale)
    #expect(card.pullRequest?.number == 9 && card.diff == SessionDiff(added: 5, removed: 2))
    // a branch and a path are drawn as such (monospaced, on one line)
    #expect(card.facts.map(\.kind) == [.text, .branch, .path])
    // the card shows the lines changed even for a session with no pull request, which its row does not
    row.pullRequest = nil
    #expect(sessionPeek(row, now: Date(), bundle: english.bundle, locale: english.locale).diff != nil && sessionPeek(row, now: Date(), bundle: english.bundle, locale: english.locale).pullRequest == nil)
    #expect(sessionPeek(SessionRow(id: "s", title: "t", workspace: "w", agent: "", state: .idle, updatedAt: Date()), now: Date(), bundle: english.bundle, locale: english.locale).facts.map(\.kind) == [.text])
}

@Test func aPeekSaysTheBackgroundProcessesApartFromTheStateAndNotInTheToneOfWork() {
    let process = BackgroundTask(id: "p", kind: "local_bash", description: "pnpm dev", agentWork: false)
    let monitor = BackgroundTask(id: "m", kind: "monitor_mcp", description: "", agentWork: false)
    let agent = BackgroundTask(id: "a", kind: "local_agent", description: "Review the diff", agentWork: true)
    func peek(_ state: SessionState, unread: Bool = false, _ background: [BackgroundTask]) -> SessionPeek {
        sessionPeek(SessionRow(id: "s", title: "t", workspace: "w", agent: "claude", state: state, updatedAt: Date(), unread: unread, background: background), now: Date(), bundle: english.bundle, locale: english.locale)
    }
    // a session left with only processes reads as any whose turn ended: quiet, or Done while unread, never the cyan of work
    let idle = peek(.idle, [process, monitor])
    #expect(idle.subtitle == "Idle" && idle.tone == .quiet && idle.background.isEmpty)
    #expect(idle.processes == [process, monitor] && idle.processes.map(\.name) == ["pnpm dev", "monitor_mcp"])
    #expect(peek(.idle, unread: true, [process]).tone == .done)
    // the processes have a line of their own beside the agent work's, and the model's turn is still violet
    let both = peek(.idle, [process, agent])
    #expect(both.tone == .background && both.background == [agent] && both.processes == [process])
    #expect(peek(.working, [process]).tone == .working && peek(.working, [process]).processes == [process])
    #expect(peek(.idle, []).processes.isEmpty)
    #expect(Copy.chatPeekRunning(bundle: english.bundle, locale: english.locale) == "Running")
}
