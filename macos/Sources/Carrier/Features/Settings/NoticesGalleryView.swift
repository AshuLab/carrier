import CarrierCore
import SwiftUI

/// A conversation that is not one: every notice the conversation and its message box can show, one under the other, drawn by the real views with
/// made-up data, so their look can be checked together and not one state at a time (a real session is only in one). Only under `--fixture`, for
/// the session the fixture lists with `sessionId`; no host is asked anything.
struct NoticesGalleryView: View {
    static let sessionId = "b4000000-0000-4000-8000-000000000001"
    static func shows(_ id: String) -> Bool { id == sessionId && CommandLine.arguments.contains("--fixture") }

    @AppStorage(Preference.appearanceMessageWidth) private var messageWidth

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s22) {
                group("Over the message box") {
                    item("A message held while the agent answers") {
                        QueuedMessageCard(text: "Estaba pensando, es posible que dejemos el sistema de tal manera para que de un select se pueda elegir el theme de iconos? Podriamos de esa manera incluir lucide por ejemplo y algunos mas a futuro, como lo ves?", interrupts: false, edit: {}, sendNow: {}, cancel: {})
                    }
                    item("The same, when sending already stops the turn") {
                        QueuedMessageCard(text: "Run the tests again.", interrupts: true, edit: {}, sendNow: {}, cancel: {})
                    }
                    item("A session that is asleep") { ClosedSessionNotice(chosen: false) }
                    item("Asleep, with something chosen that waits for the wake") { ClosedSessionNotice(chosen: true) }
                    item("An archived session") { ArchivedSessionNotice(resume: {}) }
                    item("A question the agent asks") {
                        QuestionCardView(
                            card: ApprovalCard(
                                approvalId: "g-question", question: "AskUserQuestion", tool: "AskUserQuestion", choices: [],
                                questions: [ChatQuestion(
                                    question: "What does the cache have to survive?", header: "Durability",
                                    options: [
                                        .init(label: "Nothing, it is only a speed-up", description: "A restart empties it and that is fine."),
                                        .init(label: "A restart of one node", description: "The data lives on the others and comes back."),
                                    ])]),
                            behind: 1, answer: { _, _, _ in })
                    }
                    item("A permission the agent asks for") {
                        ApprovalCardView(
                            card: ApprovalCard(
                                approvalId: "g-approval", question: "Allow Bash?", tool: "Bash", arg: "pnpm install --frozen-lockfile",
                                choices: [
                                    ChatChoice(id: "allow", label: "Yes", allow: true),
                                    ChatChoice(id: "always", label: "Yes, and do not ask again for pnpm commands", allow: true),
                                    ChatChoice(id: "deny", label: "No, tell the agent what to do differently", allow: false),
                                ]),
                            behind: 0, answer: { _, _ in })
                    }
                    item("Work the agent waits for in the background") {
                        BackgroundWorkCard(
                            tasks: [
                                BackgroundTask(id: "b1", kind: "monitor", description: "Watching the deploy of the staging branch", startedAt: Date().addingTimeInterval(-340)),
                                BackgroundTask(id: "b2", kind: "shell", description: "pnpm test --watch", startedAt: Date().addingTimeInterval(-95)),
                            ], stop: {}, stopTask: { _ in })
                    }
                    item("A new session: uncommitted files") {
                        UncommittedNotice(title: "3 files have uncommitted changes", detail: "A worktree keeps them out of the agent's way.", offersWorktree: true, useWorktree: {})
                    }
                }
                group("A new session, and the home of Sessions") {
                    item("No provider can start a session") {
                        ProblemNotice(sentences: "No provider can start a session: claude is signed out, codex is not installed.")
                    }
                    item("The chat host is older than the app") { ProblemNotice(sentences: NewSessionModel.olderHostNotice) }
                    item("The send was refused: not signed in") {
                        FailureBannerView(banner: refusalBanner(agent: "claude", reason: Refusal(code: "agent.notLoggedIn", params: ["agent": "Claude"], text: "Claude is not logged in; run `claude` once to log in")), agent: "claude", copyDetails: false, retry: nil)
                    }
                    item("The worktree's name cannot be used") { ProblemNotice(title: "That name cannot be used", detail: "A branch named feat/login already exists.") }
                    item("The folder cannot be used") { ProblemNotice(title: "Couldn't use this folder", detail: "It is not a git repository, so it has no worktrees.", failed: true) }
                    item("The chat host should be restarted (home of Sessions)") {
                        ProblemNotice(title: chatHostRestartNotice.title, detail: chatHostRestartNotice.line, symbol: .refresh)
                    }
                }
                group("In the conversation and under the box") {
                    item("A turn that failed (the last one: it can be tried again)") {
                        FailureBannerView(
                            banner: failedTurnBanner(agent: "claude", error: "The provider closed the connection before the answer was complete."),
                            agent: "claude", copyDetails: true, retry: {})
                    }
                    item("A turn that failed, no longer the last: a record") {
                        FailureBannerView(banner: failedTurnBanner(agent: "claude", error: "The provider closed the connection before the answer was complete."), agent: "claude", copyDetails: true, retry: nil)
                    }
                    item("A send the provider refuses: not signed in") {
                        FailureBannerView(
                            banner: refusalBanner(agent: "claude", reason: Refusal(code: "agent.notLoggedIn", params: ["agent": "Claude"], text: "Claude is not logged in; run `claude` once to log in")),
                            agent: "claude", copyDetails: false, retry: {})
                    }
                    item("A refusal in words (the host said no)") {
                        ProblemNotice(text: "This session is waiting for an approval; interrupt it or wait, then switch its agent")
                    }
                    item("A session that could not be read") { ProblemNotice(text: "The chat host did not answer.", failed: true) }
                    item("A dictation that failed, under the box") { ProblemNotice(title: "Dictation did not work", detail: "The microphone is in use by another app.", failed: true) }
                }
                group("On an epic's page") {
                    item("A stopped epic that needs a person") {
                        ResumeCardView(
                            card: ResumeCard(title: "Review limit reached", words: "Resuming gives it another round of review.", attention: .input, sheet: ["It runs again from the review stage."], showsButton: true),
                            store: EpicStore(), epic: EpicRef(repo: "AshuLab/carrier", issue: 12))
                    }
                    item("A stopped epic that failed") {
                        ResumeCardView(
                            card: ResumeCard(title: "Retries exhausted", words: "Resuming starts the execution again from where it stopped.", attention: .error, sheet: ["It runs again."], showsButton: true),
                            store: EpicStore(), epic: EpicRef(repo: "AshuLab/carrier", issue: 13))
                    }
                }
            }
            .padding(.horizontal, Tokens.Space.s40).padding(.vertical, Tokens.Space.s16)
            .frame(maxWidth: messageWidth.points, alignment: .leading).frame(maxWidth: .infinity)
        }
        .font(.scaled(13))
    }

    private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s18) {
            Text(title.uppercased()).font(.scaled(11, weight: .semibold)).foregroundStyle(.secondary).tracking(0.6)
            content()
        }
    }

    private func item<Content: View>(_ caption: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s6) {
            Text(caption).font(.scaled(11)).foregroundStyle(.tertiary)
            content()
        }
    }
}
