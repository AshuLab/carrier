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
    @State private var foldersOpen = false
    @State private var branchesOpen = false
    @State private var currentBranchOpen = false
    @State private var whereOpen = false
    @State private var boxFocused = false

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
                if let reason = model.noAgentReason { Text(reason).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
                if model.hostOlder { Text(NewSessionModel.olderHostNotice).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
                if model.gitMissing { HealthFixButton(tool: .git, state: .missing) }
                if model.sendSteps.isEmpty == false { sendSteps }
                if let refusal = model.refusal {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(refusal).foregroundStyle(.red).textSelection(.enabled)
                        if let hint = signInLine(refusal: refusal) { Text(hint).foregroundStyle(.secondary) }
                    }
                    .font(.callout)
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
            FlowLayout(spacing: 6) {
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
                .buttonStyle(.plain).accessibilityLabel("Workspace")
                .sheet(isPresented: $foldersOpen) { WorkspaceSheet(model: model, openHealth: openHealth).themed() }
                if model.folder != nil {
                    Button { model.clearWorkspace() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).accessibilityLabel("Clear workspace").help("Clear the workspace")
                }
                if model.loadingBranches { ProgressView().controlSize(.small) }
                if model.folder != nil {
                    if model.offersWorktree {
                        Text("on")
                        Button { whereOpen.toggle() } label: { chip(model.worktree ? "New worktree" : "Current folder", icon: model.worktree ? "square.on.square" : "folder") }
                            .buttonStyle(.plain).accessibilityLabel("Where it works")
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
            if let note = model.projectNote { Label(note, systemImage: "folder.badge.plus").font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled) }
            if let note = model.branchNote { Text(note).font(.callout).foregroundStyle(.secondary) }
            if case .problem(let reason) = model.nameState, model.worktree {
                Text(reason).font(.callout).foregroundStyle(.red).textSelection(.enabled)
            }
            if let problem = model.workspaceProblem { Text(problem).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
        }
    }

    /// The uncommitted files of the folder, under the box where the other notes about sending are: the first sentence is the title, the rest
    /// what to do, and a worktree is one tap away.
    private func uncommittedNotice(_ warning: String) -> some View {
        let split = warning.range(of: ". ")
        let title = split.map { String(warning[..<$0.lowerBound]) } ?? warning
        let detail = split.map { String(warning[$0.upperBound...]) }
        return NoticeCard(symbol: "exclamationmark", tint: .orange, title: title, detail: detail, edge: true) {
            if model.offersWorktree, model.worktree == false {
                Button("Use a worktree") { Task { await model.useWorktree(true) } }.buttonStyle(HoverTextButtonStyle(tint: .themeAccent))
            }
        }
    }

    /// The branch the chosen folder is on: a chip that opens its local branches, like the other controls.
    private var currentBranch: some View {
        Button { currentBranchOpen.toggle() } label: { chip(model.picked ?? model.workspace?.branch ?? "detached HEAD", icon: "arrow.triangle.branch") }
            .buttonStyle(.plain).accessibilityLabel("Branch of the folder")
            .sheet(isPresented: $currentBranchOpen) { BranchSheet(model: model, browsing: true).themed() }
    }

    /// What `model.sentence` says after "Work in <workspace> ".
    private var rest: String {
        let head = "Work in \(model.folder.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "") "
        return model.sentence.hasPrefix(head) ? String(model.sentence.dropFirst(head.count)) : model.sentence
    }

    /// A control of the sentence: its value and a chevron. The icon and the chevron are drawn over the text and not beside it: a `Menu`
    /// takes a label that is a text and an image apart and puts the image first, which sent the chevron to the left.
    private func chip(_ title: String, tint: Color = .primary, icon: String? = nil) -> some View {
        Text(title).fontWeight(.medium)
            .padding(.leading, icon == nil ? 0 : 17).padding(.trailing, 15)
            .overlay(alignment: .leading) {
                if let icon { Image(systemName: icon).font(.scaled(11, weight: .medium)).foregroundStyle(.secondary) }
            }
            .overlay(alignment: .trailing) { Image(systemName: "chevron.down").font(.scaled(9, weight: .bold)).foregroundStyle(.secondary) }
            .foregroundStyle(tint)
            .padding(.horizontal, 10).frame(height: controlHeight)
            .controlSurface(tint: tint)
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }

    /// What sending does, a step each: its badge, what it does in a few words and the sentence that tells it, with the names in monospace and
    /// the full path in the tooltip. The surface and the layout are the closed-session notice's.
    private var sendSteps: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(model.sendSteps, id: \.parts) { step in
                HStack(spacing: 12) {
                    Image(systemName: step.icon)
                        .font(.scaled(14, weight: .medium)).foregroundStyle(.white)
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
        .glassEffect(.regular.tint(Color.themeAccent.opacity(0.15)), in: .rect(cornerRadius: 12))
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
            Button { Task { await model.rollName() } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Pick another name").accessibilityLabel("Suggest another name")
        }
        .font(.callout.monospaced())
        .padding(.horizontal, 10).frame(height: controlHeight)
        .controlSurface()
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(nameBorder, lineWidth: 1))
        // the name is checked a moment after typing; typing again cancels the check that was waiting
        .task(id: model.worktreeName) { await model.verifyName() }
        Text("from")
        Button { branchesOpen.toggle() } label: { chip(model.startBranch ?? "Choose a branch…", icon: "arrow.triangle.branch") }
            .buttonStyle(.plain)
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
            focus: $boxFocused, commands: model.agentCommands, send: send
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
