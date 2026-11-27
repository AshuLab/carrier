import CarrierCore
import SwiftUI

/// The box of an open session, in a view of its own: what is typed in it is `model.draft`, and a view that reads it is drawn again at every
/// key, which for the whole conversation (its feed folded, filtered and laid out) made typing slow.
struct ConversationBox: View {
    @Bindable var model: ConversationModel
    @Binding var boxFocused: Bool
    /// The times the global shortcut asked this box to dictate.
    var dictations: Int
    @AppStorage(Preference.chatWhileWorking) private var whileWorking
    @AppStorage(Preference.appearanceMessageWidth) private var messageWidth
    @AppStorage(Preference.chatShowsContextUsage) private var showsContextUsage

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s8) {
            let approvals = pendingApprovals(model.rows)
            if let card = approvals.first {
                Group {
                    if card.questions.isEmpty {
                        ApprovalCardView(card: card, behind: approvals.count - 1) { approval, choice in Task { await model.answer(approval, choice: choice) } }
                    } else {
                        QuestionCardView(card: card, behind: approvals.count - 1) { approval, choice, answers in Task { await model.answer(approval, choice: choice, answers: answers) } }
                            .id(card.approvalId)
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if model.agentWork.isEmpty == false {
                BackgroundWorkCard(tasks: model.agentWork, stop: { Task { await model.stop() } }, stopTask: model.canStopTask ? { id in Task { await model.stopTask(id) } } : nil).transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if model.folderGone { FolderGoneNotice().transition(.opacity) }
            else if model.asleep { ClosedSessionNotice(chosen: model.wakeOptions.isEmpty == false).transition(.opacity) }
            if let queued = model.queued {
                QueuedMessageCard(
                    text: queued, interrupts: whileWorking == .interrupt,
                    edit: { model.editQueued() }, sendNow: { Task { await model.sendQueuedNow() } }, cancel: { model.cancelQueued() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            MessageBox(
                text: $model.draft, placeholder: Copy.chatComposerPlaceholder(), minLines: 2,
                canSend: model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false, canSendWithText: true, busy: model.busy,
                focus: $boxFocused, commands: model.shownCommands, dictationOwner: "session:\(model.sessionId)", dictateRequest: dictations,
                meter: showsContextUsage ? AnyView(ContextUsageButton(context: contextUse(model.rows), account: model.agent, store: AppUsage.store, busy: model.busy)) : nil,
                send: { Task { await model.submit(whileWorking: whileWorking) } }, stop: { Task { await model.stop() } }
            ) {
                ComposerMenuButton(
                    // the agents the host can switch the session to; with none listed (an older host) the panel shows the session's own
                    providers: model.switchTargets.isEmpty
                        ? (model.agent.isEmpty ? [] : [ProviderTab(name: model.agent, icon: AgentAccounts.harness(of: model.agent))])
                        : model.switchTargets.map { ProviderTab(name: $0.name, icon: $0.harness, available: $0.available, note: $0.note()) },
                    agent: model.pendingAgent ?? model.agent, locked: model.canSwitchNow == false,
                    options: model.shownOptions,
                    // a closed session lists what it offered when it last ran, and what is chosen waits for the message that wakes it; one the app
                    // never saw running lists nothing, and the panel says so
                    emptyNote: model.pendingAgent.map { Copy.chatComposerTakingOver(agent: $0) } ?? (model.asleep ? Copy.chatComposerAsleep() : Copy.chatComposerReading()),
                    busy: model.busy, chooseAgent: { name in model.chooseAgent(name) }, choose: { option, value in Task { await model.setOption(option, value) } }
                )
            }
            if let refusal = model.optionRefusal { ProblemNotice(text: refusal) }
            if let refusal = model.refusal {
                if model.refusedText == nil {
                    ProblemNotice(text: refusal.shown())
                } else {
                    FailureBannerView(banner: refusalBanner(agent: ProviderIdentityStore.shared.shortName(of: model.agent), reason: refusal), agent: model.agent, copyDetails: false, retry: { Task { await model.retry() } })
                }
            }
        }
        .animation(.smooth(duration: 0.25), value: model.queued)
        .animation(.smooth(duration: 0.25), value: model.asleep)
        .animation(.smooth(duration: 0.25), value: pendingApprovals(model.rows).first?.approvalId)
        // the window asks the box for its smallest size with no width at all, and a notice that wraps would answer with a word a line:
        // taller than the window (a closed session's notice made it ask for 450 points more than it had)
        .frame(minWidth: 320)
        .padding(.horizontal, Tokens.Space.s40).padding(.vertical, Tokens.Space.s12)
        .frame(maxWidth: messageWidth.points).frame(maxWidth: .infinity)
        .onAppear { boxFocused = true }
    }
}
