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
                group(Copy.noticesGalleryGroupBox()) {
                    item(Copy.noticesGalleryCaptionQueued()) {
                        QueuedMessageCard(text: Copy.noticesGallerySampleQueuedLong(), interrupts: false, edit: {}, sendNow: {}, cancel: {})
                    }
                    item(Copy.noticesGalleryCaptionQueuedInterrupts()) {
                        QueuedMessageCard(text: Copy.noticesGallerySampleQueuedShort(), interrupts: true, edit: {}, sendNow: {}, cancel: {})
                    }
                    item(Copy.noticesGalleryCaptionAsleep()) { ClosedSessionNotice(chosen: false) }
                    item(Copy.noticesGalleryCaptionAsleepChosen()) { ClosedSessionNotice(chosen: true) }
                    item(Copy.noticesGalleryCaptionArchived()) { ArchivedSessionNotice(resume: {}) }
                    item(Copy.noticesGalleryCaptionQuestion()) {
                        QuestionCardView(
                            card: ApprovalCard(
                                approvalId: "g-question", question: "AskUserQuestion", tool: "AskUserQuestion", choices: [],
                                questions: [ChatQuestion(
                                    question: Copy.noticesGallerySampleQuestion(), header: Copy.noticesGallerySampleQuestionHeader(),
                                    options: [
                                        .init(label: Copy.noticesGallerySampleOptionNothing(), description: Copy.noticesGallerySampleOptionNothingDetail()),
                                        .init(label: Copy.noticesGallerySampleOptionNode(), description: Copy.noticesGallerySampleOptionNodeDetail()),
                                    ])]),
                            behind: 1, answer: { _, _, _ in })
                    }
                    item(Copy.noticesGalleryCaptionApproval()) {
                        ApprovalCardView(
                            card: ApprovalCard(
                                approvalId: "g-approval", question: Copy.noticesGallerySampleApprovalQuestion(), tool: "Bash", arg: "pnpm install --frozen-lockfile",
                                choices: [
                                    ChatChoice(id: "allow", label: Copy.noticesGallerySampleChoiceYes(), allow: true),
                                    ChatChoice(id: "always", label: Copy.noticesGallerySampleChoiceAlways(), allow: true),
                                    ChatChoice(id: "deny", label: Copy.noticesGallerySampleChoiceNo(), allow: false),
                                ]),
                            behind: 0, answer: { _, _ in })
                    }
                    item(Copy.noticesGalleryCaptionBackground()) {
                        BackgroundWorkCard(
                            tasks: [
                                BackgroundTask(id: "b1", kind: "monitor", description: Copy.noticesGallerySampleTaskDeploy(), startedAt: Date().addingTimeInterval(-340)),
                                BackgroundTask(id: "b2", kind: "shell", description: "pnpm test --watch", startedAt: Date().addingTimeInterval(-95)),
                            ], stop: {}, stopTask: { _ in })
                    }
                    item(Copy.noticesGalleryCaptionUncommitted()) {
                        UncommittedNotice(title: Copy.noticesGallerySampleUncommittedTitle(), detail: Copy.noticesGallerySampleUncommittedDetail(), offersWorktree: true, useWorktree: {})
                    }
                }
                group(Copy.noticesGalleryGroupNewSession()) {
                    item(Copy.noticesGalleryCaptionNoProvider()) {
                        ProblemNotice(sentences: Copy.noticesGallerySampleNoProvider())
                    }
                    item(Copy.noticesGalleryCaptionOlderHost()) { ProblemNotice(sentences: Copy.newSessionOlderHost()) }
                    item(Copy.noticesGalleryCaptionNotSignedIn()) {
                        FailureBannerView(banner: refusalBanner(agent: "claude", reason: notLoggedIn), agent: "claude", copyDetails: false, retry: nil)
                    }
                    item(Copy.noticesGalleryCaptionNameUnusable()) { ProblemNotice(title: Copy.newSessionNameCannotBeUsed(), detail: Copy.noticesGallerySampleNameUnusableDetail()) }
                    item(Copy.noticesGalleryCaptionFolderUnusable()) { ProblemNotice(title: Copy.newSessionFolderFailed(), detail: Copy.noticesGallerySampleFolderUnusableDetail(), failed: true) }
                    item(Copy.noticesGalleryCaptionRestartHost()) {
                        ProblemNotice(title: chatHostRestartNotice().title, detail: chatHostRestartNotice().line, symbol: .refresh)
                    }
                }
                group(Copy.noticesGalleryGroupConversation()) {
                    item(Copy.noticesGalleryCaptionTurnFailedLast()) {
                        FailureBannerView(
                            banner: failedTurnBanner(agent: "claude", error: Copy.noticesGallerySampleTurnFailed()),
                            agent: "claude", copyDetails: true, retry: {})
                    }
                    item(Copy.noticesGalleryCaptionTurnFailedRecord()) {
                        FailureBannerView(banner: failedTurnBanner(agent: "claude", error: Copy.noticesGallerySampleTurnFailed()), agent: "claude", copyDetails: true, retry: nil)
                    }
                    item(Copy.noticesGalleryCaptionSendRefused()) {
                        FailureBannerView(
                            banner: refusalBanner(agent: "claude", reason: notLoggedIn),
                            agent: "claude", copyDetails: false, retry: {})
                    }
                    item(Copy.noticesGalleryCaptionRefusalWords()) {
                        ProblemNotice(text: Copy.noticesGallerySampleRefusalWords())
                    }
                    item(Copy.noticesGalleryCaptionUnreadable()) { ProblemNotice(text: Copy.projectsHostNoAnswer(), failed: true) }
                    item(Copy.noticesGalleryCaptionDictationFailed()) { ProblemNotice(title: Copy.chatDictationFailed(), detail: Copy.noticesGallerySampleDictationDetail(), failed: true) }
                }
                group(Copy.noticesGalleryGroupEpic()) {
                    item(Copy.noticesGalleryCaptionEpicStopped()) {
                        ResumeCardView(
                            card: ResumeCard(title: Copy.noticesGallerySampleEpicStoppedTitle(), words: Copy.noticesGallerySampleEpicStoppedWords(), attention: .input, sheet: [Copy.noticesGallerySampleEpicStoppedSheet()], showsButton: true),
                            store: EpicStore(), epic: EpicRef(repo: "AshuLab/carrier", issue: 12))
                    }
                    item(Copy.noticesGalleryCaptionEpicFailed()) {
                        ResumeCardView(
                            card: ResumeCard(title: Copy.noticesGallerySampleEpicFailedTitle(), words: Copy.noticesGallerySampleEpicFailedWords(), attention: .error, sheet: [Copy.noticesGallerySampleEpicFailedSheet()], showsButton: true),
                            store: EpicStore(), epic: EpicRef(repo: "AshuLab/carrier", issue: 13))
                    }
                }
            }
            .padding(.horizontal, Tokens.Space.s40).padding(.vertical, Tokens.Space.s16)
            .frame(maxWidth: messageWidth.points, alignment: .leading).frame(maxWidth: .infinity)
        }
        .scaledFont(13)
    }

    /// The refusal of a provider that is not signed in: the code the host gives, and its words in the language of the app.
    private var notLoggedIn: Refusal {
        let params: [String: TextParam] = ["agent": "Claude"]
        return Refusal(code: "agent.notLoggedIn", params: params, text: Copy.text("agent.notLoggedIn", params) ?? "")
    }

    private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s18) {
            Text(title.uppercased()).scaledFont(11, weight: .semibold).foregroundStyle(.secondary).tracking(0.6)
            content()
        }
    }

    private func item<Content: View>(_ caption: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s6) {
            Text(caption).scaledFont(11).foregroundStyle(.tertiary)
            content()
        }
    }
}
