import Foundation
import Testing
@testable import CarrierCore

private func section(
    _ state: SessionSection.State = .done, id: String = "a", role: String = "Builder", place: String = "Ship", engineRole: String = "author",
    profile: String? = nil, account: String? = nil, model: String? = nil, effort: String? = nil, counts: SessionCounts? = nil,
    time: String? = "31m", result: ResultCard? = nil, failure: String? = nil, duration: Int? = nil
) -> SessionSection {
    SessionSection(
        id: id, state: state, agent: "Claude", initial: "C", role: role, place: place, counts: counts, timeLabel: time, openByDefault: false,
        result: result, failure: failure, engineRole: engineRole, profile: profile, account: account, model: model, effort: effort, durationMs: duration
    )
}

private let config = Data("""
{
  "profiles": {"bot-a": {"kind": "forge", "agent": "acme-author"}, "me": {"kind": "gh"}},
  "agents": {
    "author": {"profile": "bot-a", "provider": "claude", "model": "sonnet", "effort": "high"},
    "reviewer": {"profile": "me", "provider": "codex", "model": "gpt-5", "effort": "low"}
  }
}
""".utf8)

// MARK: who

@Test func aSessionWithAProfileIsNamedByItAndTheToolMovesToTheSecondLine() {
    let text = sessionRowText(section(profile: "acme-author", account: "pro", model: "sonnet", effort: "high"))
    #expect(text.name == "acme-author")
    #expect(text.role == "Builder · Ship")
    #expect(text.tool == "Claude")
    #expect(text.details == ["account pro", "sonnet", "high"])
    #expect(text.how == "Claude · account pro · sonnet · high")
    #expect(text.letter == "A")
    #expect(text.identified)
}

@Test func aSessionWithNoProfileKeepsTheToolsNameAndLeavesOutWhatItDoesNotKnow() {
    let text = sessionRowText(section(model: "sonnet"))
    #expect(text.name == "Claude")
    #expect(text.tool == nil)
    #expect(text.how == "sonnet")
    #expect(text.letter == "C")
    #expect(text.identified == false)
    #expect(sessionRowText(section()).how.isEmpty)
    // an empty profile is none
    #expect(sessionRowText(section(profile: "")).name == "Claude")
}

@Test func theConfigNamesTheForgeBotOfTheRoleAndNoOneForAGhProfile() {
    let roles = RoleIdentities(config: config)
    #expect(roles.resolved(section(engineRole: "author")).profile == "acme-author")
    // the person's own login is not in the file
    #expect(roles.resolved(section(engineRole: "reviewer")).profile == nil)
    #expect(roles.resolved(section(engineRole: "")).profile == nil)
}

@Test func aProfileTheEngineSentIsNeverReplacedByTheConfig() {
    #expect(RoleIdentities(config: config).resolved(section(profile: "other-bot")).profile == "other-bot")
}

@Test func theRolesEffortOnlyGoesToASessionThatRanOnTheRolesModel() {
    let roles = RoleIdentities(config: config)
    #expect(roles.resolved(section(model: "sonnet")).effort == "high")
    // a failover to another model did not run with that effort
    #expect(roles.resolved(section(model: "gpt-5")).effort == nil)
    #expect(roles.resolved(section(model: "sonnet", effort: "max")).effort == "max")
    #expect(roles.resolved(section()).effort == nil)
}

@Test func noConfigOrOneThatIsNotAnObjectNamesNobody() {
    #expect(RoleIdentities(config: nil).resolved(section()) == section())
    #expect(RoleIdentities(config: Data("[1]".utf8)).resolved(section()) == section())
    #expect(RoleIdentities.none.resolved(section()) == section())
}

@Test func theSessionsReplyFillsTheIdentityItHas() {
    let agent = PanelSnapshot.Agent(harness: "claude", model: "sonnet", provider: "pro")
    var reply = SessionsReply.Session(
        executionId: "x", stage: "fix", role: "author", round: 2, agent: agent, status: "finished", startedAt: 1000, finishedAt: 61_000, resume: nil
    )
    reply.profile = "acme-author"
    let built = sessionList(SessionsReply(sessions: [reply])).sections[0]
    #expect(built.profile == "acme-author")
    #expect(built.account == "pro")
    #expect(built.model == "sonnet")
    #expect(built.engineRole == "author")
    #expect(built.durationMs == 60_000)
    reply.profile = nil
    #expect(sessionList(SessionsReply(sessions: [reply])).sections[0].profile == nil)
}

@Test func aReplyFromAnEngineThatSendsAProfileDecodes() throws {
    let json = Data("""
    {"executionId":"x","stage":"ship","role":"author","round":null,"agent":{"harness":"claude","model":"m","provider":null},
     "status":"running","startedAt":1,"finishedAt":null,"resume":null,"profile":"acme-author"}
    """.utf8)
    #expect(try JSONDecoder().decode(SessionsReply.Session.self, from: json).profile == "acme-author")
}

// MARK: the summary line

private func text(_ summary: SessionSummary) -> String { summary.text }

@Test func aRunningSessionSaysItIsWorkingSinceWhenAndHowManyCalls() {
    let running = section(.running, counts: SessionCounts(calls: 62), time: "since 16:09")
    #expect(sessionSummary(running, open: true) == sessionSummary(running, open: false))
    #expect(text(sessionSummary(running, open: true)) == "Working, since 16:09, 62 calls")
    #expect(text(sessionSummary(section(.running, time: "since 16:09"), open: true)) == "Working, since 16:09")
}

@Test func aStoppedSessionShowsItsBadgeAndItsReason() {
    #expect(sessionSummary(section(.stopped, time: nil, failure: "usage_limit: resets 3:10am"), open: false) == .stopped(reason: "usage_limit: resets 3:10am"))
    #expect(sessionSummary(section(.stopped, time: nil), open: true) == .stopped(reason: nil))
    #expect(text(.stopped(reason: "killed: SIGKILL")) == "stopped, killed: SIGKILL")
}

@Test func anOpenSessionSaysItsCountsAndHowLongItTook() {
    let counts = SessionCounts(calls: 229, edits: 23, added: 10, removed: 2, tests: 27, errors: 9)
    #expect(text(sessionSummary(section(counts: counts), open: true)) == "229 calls, 23 edits +10 −2, 27 test runs, 9 errors, 31m")
    #expect(text(sessionSummary(section(counts: SessionCounts(calls: 1)), open: true)) == "1 call, 31m")
    #expect(text(sessionSummary(section(counts: nil), open: true)) == "31m")
    let errors = sessionSummary(section(counts: SessionCounts(calls: 3, errors: 2)), open: true)
    guard case .line(let spans) = errors else { Issue.record("not a line"); return }
    #expect(spans.filter { $0.style == .red }.map(\.text) == ["2", "errors"])
}

@Test func aFoldedSessionSaysHowItEndedInBoldThenTheVerdictAndTheTime() {
    let done = ResultCard(outcome: "Completed", tone: .good, ci: .init(verdict: "passed", evidence: "ok"), reason: nil)
    let summary = sessionSummary(section(counts: SessionCounts(calls: 5), result: done), open: false)
    #expect(text(summary) == "Completed, CI passed, 31m")
    guard case .line(let spans) = summary else { Issue.record("not a line"); return }
    #expect(spans.first == SummarySpan(text: "Completed", style: .strong))
    let review = ResultCard(outcome: "Changes requested", tone: .warning, ci: nil, reason: nil)
    #expect(text(sessionSummary(section(result: review), open: false)) == "Changes requested, 31m")
    // no result: the counts, as when it is open
    #expect(text(sessionSummary(section(counts: SessionCounts(calls: 4)), open: false)) == "4 calls, 31m")
    // open, the counts win over the outcome
    #expect(text(sessionSummary(section(counts: SessionCounts(calls: 4), result: done), open: true)) == "4 calls, 31m")
}

@Test func theRowsLabelSaysWhoWhatAndWhetherItIsOpen() {
    let row = section(profile: "acme-author", account: "pro", model: "sonnet", counts: SessionCounts(calls: 4))
    #expect(sessionRowLabel(row, open: true) == "acme-author. Builder · Ship. Claude · account pro · sonnet. 4 calls, 31m. Open")
    #expect(sessionRowLabel(section(), open: false) == "Claude. Builder · Ship. 31m. Folded")
}

// MARK: earlier sessions

private func many(_ count: Int) -> [SessionSection] {
    let roles = ["Builder", "Reviewer", "Fixer"]
    return (0..<count).map { section(.done, id: "s\($0)", role: roles[$0 % 3], duration: 15 * 60_000) }
}

@Test func upToFiveSessionsAreAllShownAndTheSixthCutsTheOldestBehindARow() {
    for count in 0...5 {
        let split = earlierSessions(many(count))
        #expect(split.earlier == nil)
        #expect(split.recent.count == count)
    }
    let six = earlierSessions(many(6))
    #expect(six.earlier?.sections.map(\.id) == ["s0"])
    #expect(six.recent.map(\.id) == ["s1", "s2", "s3", "s4", "s5"])
    let twelve = earlierSessions(many(12))
    #expect(twelve.earlier?.sections.count == 7)
    #expect(twelve.recent.map(\.id) == (7..<12).map { "s\($0)" })
}

@Test func theEarlierRowSaysHowManyWhichRolesOnceEachAndTheTimeTogether() {
    let earlier = EarlierSessions(sections: Array(many(4)))
    #expect(earlier.title == "4 earlier sessions")
    #expect(earlier.detail == "Builder, Reviewer, Fixer · 1h 00m")
    #expect(earlier.label == "4 earlier sessions, Builder, Reviewer, Fixer · 1h 00m")
    let one = EarlierSessions(sections: [section(role: "Builder", duration: 31 * 60_000)])
    #expect(one.title == "1 earlier session")
    #expect(one.detail == "Builder · 31m")
    // no time known: the roles alone
    #expect(EarlierSessions(sections: [section(role: "Fixer")]).detail == "Fixer")
}
