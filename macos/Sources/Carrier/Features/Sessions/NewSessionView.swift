import AppKit
import CarrierCore
import SwiftUI

/// The draft of a new session in the centre (chat-ui-where2.html): the question, the sentence that says where it works (the workspace,
/// then a new worktree or the current folder), and the box with the agent chip and Send. Sending opens the session and `opened` selects it.
struct NewSessionView: View {
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
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            // the title carries the page alone: large, and centred however many lines it takes
            VStack(spacing: 6) {
                Text("What do you want to work on?").font(.scaled(28, weight: .semibold))
                Text("Pick where it works, then write.").font(.title3).foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center).frame(maxWidth: .infinity)
            .padding(.bottom, 14)
            VStack(alignment: .leading, spacing: 16) {
                sentence
                box
                if let warning = model.warning { uncommittedNotice(warning) }
                if let reason = model.noAgentReason { ProblemNotice(sentences: reason) }
                if model.hostOlder { ProblemNotice(sentences: NewSessionModel.olderHostNotice) }
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
        .padding(.horizontal, 40)
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
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 8) {
                Text("Work in")
                Button {
                    if foldersOpen == false { model.openPicker() }
                    foldersOpen.toggle()
                } label: {
                    chip(
                        model.folder.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Choose a workspace…",
                        tint: model.folder == nil ? .orange : .primary
                    )
                }
                .buttonStyle(SelectButtonStyle()).accessibilityLabel("Workspace")
                .sheet(isPresented: $foldersOpen) { AddProjectSheet(mode: .newSession, model: ProjectsModel.shared, recent: model.recent, newSession: model, openHealth: openHealth).themed() }
                // GitHub's branches are being read, or the fetch that choosing a project starts is bringing its own up to date
                if model.loadingBranches || model.fetching { ProgressView().controlSize(.small).accessibilityLabel(model.fetching ? "Fetching branches" : "Reading branches") }
                if model.folder != nil {
                    if model.offersWorktree {
                        Text("on")
                        Button { whereOpen.toggle() } label: { chip(model.worktree ? "New worktree" : "Current folder", icon: model.worktree ? .copy : .folder) }
                            .buttonStyle(SelectButtonStyle()).accessibilityLabel("Where it works")
                            .sheet(isPresented: $whereOpen) { WhereItWorksSheet(model: model).themed() }
                        if model.worktree { worktreeControls } else { currentBranch }
                    } else {
                        Text(rest)
                    }
                }
            }
            .font(.body).foregroundStyle(.secondary)
            .accessibilityElement(children: .contain)
            if model.branchesPartial { Text("Only the first branches GitHub lists are offered; the others can be checked out once the repository is on this Mac.").font(.subheadline).foregroundStyle(.secondary) }
            if let note = model.projectNote { Label(note, icon: .folderPlus).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled) }
            if model.offersAddAsProject {
                // a folder chosen with Open a folder stays a plain workspace until the person adds it
                HStack(spacing: 8) {
                    Button { Task { await model.addAsProject() } } label: { Label("Add as project", icon: .folderPlus).labelStyle(.titleAndIcon) }
                        .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
                        .help("Keep this folder in your projects")
                    if let problem = model.addProjectProblem { ProblemLine(text: problem, font: .scaled(12)) }
                }
            }
            if case .problem(let reason) = model.nameState, model.worktree {
                ProblemNotice(title: "That name cannot be used", detail: reason)
            }
            if let problem = model.workspaceProblem { ProblemNotice(title: "Couldn't use this folder", detail: problem, failed: true) }
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
        Button { currentBranchOpen.toggle() } label: { chip(model.picked ?? model.workspace?.branch ?? "detached HEAD", icon: .gitBranch) }
            .buttonStyle(SelectButtonStyle()).accessibilityLabel("Branch of the folder")
            .sheet(isPresented: $currentBranchOpen) { BranchSheet(model: model, browsing: true).themed() }
    }

    /// What `model.sentence` says after "Work in <workspace> ".
    private var rest: String {
        let head = "Work in \(model.folder.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "") "
        return model.sentence.hasPrefix(head) ? String(model.sentence.dropFirst(head.count)) : model.sentence
    }

    /// A control of the sentence, with the face of every select of the app: an icon if it has one, its value and `SelectChevron` after it. Its
    /// button takes `SelectButtonStyle`.
    private func chip(_ title: String, tint: Color = .primary, icon: AppIcon? = nil) -> some View {
        HStack(spacing: 6) {
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
        VStack(alignment: .leading, spacing: 12) {
            ForEach(model.sendSteps, id: \.parts) { step in
                HStack(spacing: 12) {
                    Glyph(step.icon, size: 14, bold: true).foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        // the accent a little deepened, with a faint rim of light: the badge of the closed-session notice
                        .background {
                            RoundedRectangle(cornerRadius: 8).fill(Color.themeAccent.mix(with: .black, by: 0.18))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
                        }
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(step.title).fontWeight(.semibold)
                        step.parts.reduce(Text("")) { text, part in
                            switch part {
                            case .text(let words): Text("\(text)\(Text(words))")
                            case .code(let name): Text("\(text)\(Text(name).font(.scaled(11).monospaced().weight(.medium)).foregroundStyle(.primary))")
                            }
                        }
                        .font(.scaled(11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        .help(step.help ?? "")
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .font(.scaled(12)).padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .chatSurface(.regular.tint(Color.themeAccent.opacity(0.15)), flat: Color.themeAccent.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }

    /// The fixed `carrier/` prefix, the name (typed over in place) with ↻, and the branch it starts from.
    @ViewBuilder private var worktreeControls: some View {
        HStack(spacing: 8) {
            // the prefix and the name are one word to the eye: no space between them
            HStack(spacing: 0) {
                Text(worktreeBranchPrefix).foregroundStyle(.secondary)
                TextField("name", text: $model.worktreeName)
                    .textFieldStyle(.plain).autocorrectionDisabled().fixedSize()
                    .foregroundStyle(nameColor).accessibilityLabel("Worktree name")
            }
            Button { Task { await model.rollName() } } label: { Glyph(.refresh, size: 13) }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Pick another name").accessibilityLabel("Suggest another name")
        }
        .font(.callout.monospaced())
        .padding(.horizontal, 10).frame(height: controlHeight)
        .controlSurface()
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(nameBorder, lineWidth: 1))
        // the name is checked a moment after typing; typing again cancels the check that was waiting
        .task(id: model.worktreeName) { await model.verifyName() }
        Text("from")
        // the chip wears the colour of the side the worktree is cut from: the remote copy or the local branch
        Button { branchesOpen.toggle() } label: { chip(model.startPoint?.ref ?? "Choose a branch…", tint: model.startPoint?.side?.tint ?? .primary, icon: model.startPoint?.side?.icon ?? .gitBranch) }
            .buttonStyle(SelectButtonStyle()).accessibilityLabel("Start branch")
            .accessibilityValue(model.startPoint.map { "\($0.side?.tabTitle ?? "Local") \($0.ref)" } ?? "none chosen")
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
            text: $model.text, placeholder: model.folder == nil ? "Choose a workspace to start…" : "Write the first message…",
            canSend: model.canSend, canSendWithText: model.canSendWithText, sendHelp: model.canSend ? "Send" : model.hostOlder ? NewSessionModel.olderHostNotice : model.noAgentReason ?? "Choose a workspace and write a message",
            focus: $boxFocused, commands: model.agentCommands, dictationOwner: "new-session", dictateRequest: dictations, send: send
        ) {
            ComposerMenuButton(
                providers: model.agents.map { ProviderTab(name: $0.name, icon: $0.harness, available: $0.available, note: $0.note) }, agent: model.agent ?? "",
                options: model.shownOptions,
                emptyNote: model.loadingOptions ? "Reading what the provider offers…" : "Each provider's models will be listed here.",
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
            if offersWorktree { Button("Use a worktree", action: useWorktree).buttonStyle(NoticeActionStyle()) }
        }
    }
}
