import AppKit
import CarrierCore
import SwiftUI

/// The draft of a new session in the centre (chat-ui-where2.html): the question, the sentence that says where it works (the workspace,
/// then a new worktree or the current folder), and the box with the agent chip and Send. Sending opens the session and `opened` selects it.
struct NewSessionView: View {
    @Environment(\.pieceTheme) private var theme
    @Bindable var model: NewSessionModel
    /// Opens the Health tab of Settings.
    let openHealth: () -> Void
    let opened: (String) -> Void
    /// The last shortcut that asked something of the box (focus it, dictate into it), as the conversation's.
    var request: ConversationRequest?
    @State private var foldersOpen = false
    @State private var branchesOpen = false
    @State private var currentBranchOpen = false
    @State private var whereOpen = false
    @State private var boxFocused = false
    /// The times the global shortcut asked the box to dictate.
    @State private var dictations = 0

    var body: some View {
        VStack(spacing: Tokens.Space.s14) {
            Spacer(minLength: 0)
            // the title carries the page alone: large, and centred however many lines it takes
            VStack(spacing: Tokens.Space.s6) {
                Text(Copy.newSessionTitle()).scaledFont(28, weight: .semibold)
                Text(Copy.newSessionSubtitle()).font(.title3).foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center).frame(maxWidth: .infinity)
            .padding(.bottom, Tokens.Space.s14)
            VStack(alignment: .leading, spacing: Tokens.Space.s16) {
                sentence
                box
                if let warning = model.warning { uncommittedNotice(warning) }
                if let reason = model.noAgentReason { ProblemNotice(sentences: reason) }
                if model.hostOlder { ProblemNotice(sentences: model.olderHostNotice) }
                if model.gitMissing { HealthFixButton(tool: .git, state: .missing) }
                if model.sendSteps.isEmpty == false { sendSteps }
                if let refusal = model.refusal {
                    // the same banner the conversation shows for a refused send, with the line that says where to sign in when that is why
                    FailureBannerView(banner: refusalBanner(agent: ProviderIdentityStore.shared.shortName(of: model.agent ?? ""), reason: refusal), agent: model.agent, copyDetails: false, retry: nil)
                }
            }
            // never narrower than 320: the window asks for its smallest size with no width, and the notes under the sentence would be a word a line
            .frame(minWidth: 320, maxWidth: 820)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Tokens.Space.s40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // a workspace's + while the draft is open asks again, for another folder
        .task(id: model.starts) {
            await model.load()
            await model.loadOptions()
        }
        .onAppear { boxFocused = true }
        .onChange(of: request) {
            switch request?.action {
            case .focusBox: boxFocused = true
            case .dictate: dictations += 1
            default: break
            }
        }
        // the health arrives after the draft opened, or changes when the app comes back active: the provider follows what can be chosen
        // `git` goes missing while a worktree is chosen: back to the current folder
        .onChange(of: model.gitMissing) { Task { await model.useWorktree(false) } }
        .onChange(of: model.agents) {
            model.pickAvailableAgent()
            Task { await model.loadOptions() }
        }
    }

    /// "Work in <workspace> on <Current folder | New worktree>": the workspace is a chip that opens the folders, and where it works
    /// is another. A new worktree shows the name it will have (with ↻, and the name is typed over in place) and the branch it starts from;
    /// the other cases (no git repository, a bare one, the host not answering yet) are said in words, as `model.sentence` has them.
    @ViewBuilder private var sentence: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s6) {
            FlowLayout(spacing: Tokens.Space.s8) {
                Text(Copy.newSessionWorkIn())
                Button {
                    if foldersOpen == false { model.openPicker() }
                    foldersOpen.toggle()
                } label: {
                    chip(
                        model.folder.map { URL(fileURLWithPath: $0).lastPathComponent } ?? Copy.newSessionChooseWorkspace(),
                        tint: model.folder == nil ? .orange : .primary
                    )
                }
                .buttonStyle(SelectButtonStyle()).accessibilityLabel(Copy.newSessionWorkspace())
                .sheet(isPresented: $foldersOpen) { AddProjectSheet(mode: .newSession, model: ProjectsModel.shared, recent: model.recent, newSession: model, openHealth: openHealth).themed() }
                // GitHub's branches are being read, or the fetch that choosing a project starts is bringing its own up to date
                if model.loadingBranches || model.fetching { ProgressView().controlSize(.small).accessibilityLabel(model.fetching ? Copy.newSessionFetchingBranches() : Copy.newSessionReadingBranches()) }
                if model.folder != nil {
                    if model.offersWorktree {
                        Text(Copy.newSessionOn())
                        Button { whereOpen.toggle() } label: { chip(model.worktree ? Copy.newSessionNewWorktree() : Copy.newSessionCurrentFolder(), icon: model.worktree ? .copy : .folder) }
                            .buttonStyle(SelectButtonStyle()).accessibilityLabel(Copy.newSessionWhereItWorks())
                            .sheet(isPresented: $whereOpen) { WhereItWorksSheet(model: model).themed() }
                        if model.worktree { worktreeControls } else { currentBranch }
                    } else {
                        Text(model.sentenceRest)
                    }
                }
            }
            .font(.body).foregroundStyle(.secondary)
            .accessibilityElement(children: .contain)
            if model.branchesPartial { Text(Copy.newSessionBranchesPartial()).font(.subheadline).foregroundStyle(.secondary) }
            if let note = model.projectNote { Label(note, icon: .folderPlus).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled) }
            if model.offersAddAsProject {
                // a folder chosen with Open a folder stays a plain workspace until the person adds it
                HStack(spacing: Tokens.Space.s8) {
                    Button { Task { await model.addAsProject() } } label: { Label(Copy.newSessionAddAsProject(), icon: .folderPlus).labelStyle(.titleAndIcon) }
                        .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
                        .help(Copy.newSessionAddAsProjectHelp())
                    if let problem = model.addProjectProblem { ProblemLine(text: problem, size: 12) }
                }
            }
            if case .problem(let reason) = model.nameState, model.worktree {
                ProblemNotice(title: Copy.newSessionNameCannotBeUsed(), detail: reason)
            }
            if let problem = model.workspaceProblem { ProblemNotice(title: Copy.newSessionFolderFailed(), detail: problem, failed: true) }
        }
    }

    /// The uncommitted files of the folder, under the box where the other notes about sending are: the first sentence is the title, the rest
    /// what to do, and a worktree is one tap away.
    private func uncommittedNotice(_ warning: String) -> some View {
        let parts = splitNotice(warning)
        return UncommittedNotice(title: parts.title, detail: parts.detail, offersWorktree: model.offersWorktree && model.worktree == false, useWorktree: { Task { await model.useWorktree(true) } })
    }

    /// The branch the chosen folder is on: a chip that opens its local branches, like the other controls.
    private var currentBranch: some View {
        Button { currentBranchOpen.toggle() } label: { chip(model.picked ?? model.workspace?.branch ?? Copy.newSessionDetachedHead(), icon: .gitBranch) }
            .buttonStyle(SelectButtonStyle()).accessibilityLabel(Copy.newSessionBranchOfFolder())
            .sheet(isPresented: $currentBranchOpen) { BranchSheet(model: model, browsing: true).themed() }
    }

    /// A control of the sentence, with the face of every select of the app: an icon if it has one, its value and `SelectChevron` after it. Its
    /// button takes `SelectButtonStyle`.
    private func chip(_ title: String, tint: Color = .primary, icon: AppIcon? = nil) -> some View {
        HStack(spacing: Tokens.Space.s6) {
            if let icon { Glyph(icon, size: 13).foregroundStyle(.secondary).frame(width: 15) }
            Text(title).fontWeight(.medium).foregroundStyle(tint)
            SelectChevron()
        }
        // with the button's 4 pt above and below, as tall as the worktree's name field
        .frame(height: controlHeight - 8)
    }

    /// What sending does, a step each: its badge, what it does in a few words and the sentence that tells it, with the names in monospace and
    /// the full path in the tooltip. The surface and the layout are the closed-session notice's.
    private var sendSteps: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s12) {
            ForEach(model.sendSteps, id: \.parts) { step in
                HStack(spacing: Tokens.Space.s12) {
                    Glyph(step.icon, size: 14, bold: true).foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        // the accent a little deepened, with a faint rim of light: the badge of the closed-session notice
                        .background {
                            RoundedRectangle(cornerRadius: Tokens.Radius.control).fill(theme.accent.mix(with: .black, by: 0.18))
                                .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.control).strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
                        }
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                        Text(step.title).fontWeight(.semibold)
                        step.parts.reduce(Text("")) { text, part in
                            switch part {
                            case .text(let words): Text("\(text)\(Text(words))")
                            case .code(let name): Text("\(text)\(Text(name).monospaced().fontWeight(.medium).foregroundStyle(.primary))")
                            }
                        }
                        .scaledFont(11).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        .help(step.help ?? "")
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .scaledFont(12).padding(Tokens.Space.s12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .chatSurface(.regular.tint(theme.accent.opacity(0.15)), flat: theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
        .accessibilityElement(children: .contain)
    }

    /// The fixed `carrier/` prefix, the name (typed over in place) with ↻, and the branch it starts from.
    @ViewBuilder private var worktreeControls: some View {
        HStack(spacing: Tokens.Space.s8) {
            // the prefix and the name are one word to the eye: no space between them
            HStack(spacing: Tokens.Space.none) {
                Text(worktreeBranchPrefix).foregroundStyle(.secondary)
                TextField(Copy.newSessionNamePlaceholder(), text: $model.worktreeName)
                    .textFieldStyle(.plain).autocorrectionDisabled().fixedSize()
                    .foregroundStyle(nameColor).accessibilityLabel(Copy.newSessionWorktreeName())
            }
            Button { Task { await model.rollName() } } label: { Glyph(.refresh, size: 13) }
                .buttonStyle(.plain).foregroundStyle(.secondary).help(Copy.newSessionPickAnother()).accessibilityLabel(Copy.newSessionSuggestAnother())
        }
        .font(.callout.monospaced())
        .padding(.horizontal, Tokens.Space.s10).frame(height: controlHeight)
        .controlSurface()
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.control).strokeBorder(nameBorder, lineWidth: 1))
        // the name is checked a moment after typing; typing again cancels the check that was waiting
        .task(id: model.worktreeName) { await model.verifyName() }
        Text(Copy.newSessionFrom())
        // the chip wears the colour of the side the worktree is cut from: the remote copy or the local branch
        Button { branchesOpen.toggle() } label: { chip(model.startPoint?.ref ?? Copy.newSessionChooseBranch(), tint: model.startPoint?.side?.tint ?? .primary, icon: model.startPoint?.side?.icon ?? .gitBranch) }
            .buttonStyle(SelectButtonStyle()).accessibilityLabel(Copy.newSessionStartBranch())
            .accessibilityValue(model.startPoint.map { "\(($0.side ?? .local).tabTitle()) \($0.ref)" } ?? Copy.newSessionNoneChosen())
            .sheet(isPresented: $branchesOpen) { BranchSheet(model: model).themed() }
    }

    private var nameColor: Color {
        if case .problem = model.nameState { .red } else { .primary }
    }

    private var nameBorder: Color {
        if case .problem = model.nameState { .red } else { .clear }
    }

    /// The first message and what it runs with: the message box shared with the open session, with the one button for the provider, the
    /// model, the reasoning and the access.
    private var box: some View {
        MessageBox(
            text: $model.text, placeholder: model.folder == nil ? Copy.newSessionPlaceholderNone() : Copy.newSessionPlaceholderWrite(),
            canSend: model.canSend, canSendWithText: model.canSendWithText, sendHelp: model.canSend ? Copy.newSessionSend() : model.hostOlder ? model.olderHostNotice : model.noAgentReason ?? Copy.newSessionSendHelp(),
            focus: $boxFocused, commands: model.agentCommands, dictationOwner: "new-session", dictateRequest: dictations, send: send
        ) {
            ComposerMenuButton(
                providers: model.agents.map { ProviderTab(name: $0.name, icon: $0.harness, available: $0.available, note: $0.note()) }, agent: model.agent ?? "",
                options: model.shownOptions,
                emptyNote: model.loadingOptions ? Copy.newSessionReadingOptions() : Copy.newSessionEmptyOptions(),
                chooseAgent: { name in
                    model.agent = name
                    Task { await model.loadOptions() }
                },
                choose: { option, value in model.choose(option: option, value: value) }
            )
        }
        // nothing to write to until a workspace is chosen
        .opacity(model.folder == nil ? 0.55 : 1)
    }

    private func send() {
        Task { if let id = await model.send() { opened(id) } }
    }
}

/// The uncommitted files of the folder, as a notice under the box: the first sentence is the title, the rest what to do, and a worktree is one tap away.
struct UncommittedNotice: View {
    let title: String
    let detail: String?
    let offersWorktree: Bool
    let useWorktree: () -> Void

    var body: some View {
        NoticeCard(symbol: .exclamation, tint: .orange, title: title, detail: detail) {
            if offersWorktree { Button(Copy.newSessionUseWorktree(), action: useWorktree).buttonStyle(NoticeActionStyle()) }
        }
    }
}
