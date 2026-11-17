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
    #expect(card.facts.map(\.label) == ["Where", "Branch", "Folder", "Agent", "Turns"])
    #expect(card.facts.map(\.value) == ["Worktree", "carrier/void-corsair-pylon", "/srv/wt/void-corsair-pylon", "claude", "3"])
    // a long branch or folder is drawn on one line and an agent as its account, so each fact says what it is
    #expect(card.facts.map(\.kind) == [.text, .branch, .path, .agent, .text])
    #expect(card.timeline == "updated 2 hours ago")
}

@Test func aSessionInThePlainFolderSaysBaseFolderAndOneWaitingForYouSaysSo() {
    let row = SessionRow(id: "s2", title: "t", workspace: "web", agent: "", state: .waiting, updatedAt: Date(), folder: "")
    let card = sessionPeek(row, now: Date())
    #expect(card.subtitle == "Waiting for you" && card.tone == .attention && card.lastMessage == nil)
    #expect(card.facts == [.init(label: "Where", value: "Base folder")])
}

@Test func theStateOfASessionIsSaidInTheWordsAndColourOfItsRow() {
    func peek(_ state: SessionState, unread: Bool = false) -> SessionPeek {
        sessionPeek(SessionRow(id: "s", title: "t", workspace: "w", agent: "", state: state, updatedAt: Date(), unread: unread), now: Date())
    }
    #expect(peek(.working).subtitle == "Working…" && peek(.working).tone == .working)
    #expect(peek(.idle).subtitle == "Idle" && peek(.idle).tone == .quiet)
    // the row says Done for a turn that ended and has not been opened, so the card does too
    #expect(peek(.idle, unread: true).subtitle == "Done" && peek(.idle, unread: true).tone == .done)
}
