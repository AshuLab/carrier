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
            NewSessionMark()
            VStack(spacing: 4) {
                Text("What do you want to work on?").font(.title2.weight(.semibold))
                Text("Pick where it works, then write.").font(.callout).foregroundStyle(.secondary)
            }
            .padding(.bottom, 10)
            VStack(alignment: .leading, spacing: 16) {
                sentence
                box
                if let reason = model.noAgentReason { Text(reason).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
                ForEach(model.agents.filter { $0.fix != nil }, id: \.name) { agent in
                    HStack(spacing: 8) {
                        Text("\(agent.name) is \(agent.note ?? "unavailable"):").font(.callout).foregroundStyle(.secondary)
                        HealthFixButton(tool: .agent(harness: agent.harness), state: agent.state)
                    }
                }
                if model.gitMissing { HealthFixButton(tool: .git, state: .missing) }
                if model.gitMissing || model.agents.contains(where: { $0.state.blocks }) {
                    Button("Open Health in Settings", action: openHealth).buttonStyle(.link).font(.callout)
                }
                if model.worktree, let branch = model.startBranch {
                    Label("Creates a worktree on the new branch \(worktreeBranchPrefix)\(model.worktreeName) from \(branch). The base folder stays as it is.", systemImage: "arrow.triangle.branch")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                }
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
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // nothing scrolls under the toolbar here, so it takes the page's own colour and not the system's band
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .task {
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
                        model.cloningName ?? model.folder.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Choose a workspace…",
                        tint: model.folder == nil && model.cloning == nil ? .orange : .primary
                    )
                }
                .buttonStyle(.plain).accessibilityLabel("Workspace")
                .sheet(isPresented: $foldersOpen) { WorkspaceSheet(model: model, openHealth: openHealth) }
                if let repo = model.cloning {
                    ProgressView().controlSize(.small)
                    Text("Cloning \(repo)…")
                }
                if model.folder != nil {
                    if model.offersWorktree {
                        Text("on")
                        Button { whereOpen.toggle() } label: { chip(model.worktree ? "New worktree" : "Current folder", icon: model.worktree ? "square.on.square" : "folder") }
                            .buttonStyle(.plain).accessibilityLabel("Where it works")
                            .sheet(isPresented: $whereOpen) { WhereItWorksSheet(model: model) }
                        if model.worktree { worktreeControls } else { currentBranch }
                    } else {
                        Text(rest)
                    }
                }
            }
            .font(.body).foregroundStyle(.secondary)
            .accessibilityElement(children: .contain)
            if let note = model.watchNote {
                Label(note, systemImage: model.watchFailed ? "exclamationmark.triangle.fill" : "eye.fill").font(.subheadline).foregroundStyle(model.watchFailed ? .orange : .secondary).textSelection(.enabled)
            }
            if let warning = model.warning { Text(warning).font(.callout).foregroundStyle(.orange) }
            if case .problem(let reason) = model.nameState, model.worktree {
                Text(reason).font(.callout).foregroundStyle(.red).textSelection(.enabled)
            }
            if let problem = model.workspaceProblem { Text(problem).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            if let problem = model.cloneProblem { Text(problem).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
        }
    }

    /// The branch the chosen folder is on: a chip that opens its local branches, like the other controls.
    private var currentBranch: some View {
        Button { currentBranchOpen.toggle() } label: { chip(model.workspace?.branch ?? "detached HEAD", icon: "arrow.triangle.branch") }
            .buttonStyle(.plain).accessibilityLabel("Branch of the folder")
            .sheet(isPresented: $currentBranchOpen) { BranchSheet(model: model, browsing: true) }
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
                if let icon { Image(systemName: icon).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary) }
            }
            .overlay(alignment: .trailing) { Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary) }
            .foregroundStyle(tint)
            .padding(.horizontal, 10).frame(height: controlHeight)
            .controlSurface(tint: tint)
            .contentShape(RoundedRectangle(cornerRadius: 8))
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
            .sheet(isPresented: $branchesOpen) { BranchSheet(model: model) }
    }

    private var nameColor: Color {
        if case .problem = model.nameState { .red } else { .primary }
    }

    private var nameBorder: Color {
        if case .problem = model.nameState { .red } else { .clear }
    }

    /// The first message and what it runs with: the message box shared with the open session, with the provider and the selects the
    /// host cannot list yet.
    private var box: some View {
        MessageBox(
            text: $model.text, placeholder: model.folder == nil ? "Choose a workspace to start…" : "Write the first message…",
            canSend: model.canSend, sendHelp: model.canSend ? "Send" : model.noAgentReason ?? "Choose a workspace and write a message",
            focus: $boxFocused, commands: model.agentCommands, send: send
        ) {
            providerSelect
            if model.shownOptions.isEmpty {
                // until the host has listed them (a few seconds the first time), or when it cannot
                ComposerSelect(title: "Model", icon: "cpu", note: model.loadingOptions ? "Reading what the provider offers…" : "Each provider's models will be listed here.")
                ComposerSelect(title: "Reasoning", icon: "brain", note: model.loadingOptions ? "Reading what the provider offers…" : "How much the agent thinks before it answers.")
                ComposerSelect(title: "Access", icon: "lock.shield", note: model.loadingOptions ? "Reading what the provider offers…" : "What the agent may do without asking you.")
            } else {
                optionSelects(model.shownOptions) { option, value in model.choose(option: option, value: value) }
            }
        }
        // nothing to write to until a workspace is chosen
        .opacity(model.folder == nil ? 0.55 : 1)
    }

    /// The agent the session starts with, from the host's list; one that is not installed or signed out is shown and cannot be chosen.
    private var providerSelect: some View {
        ComposerSelect(
            title: "Provider", icon: "sparkle", selected: model.agent, showsValue: true,
            choices: model.agents.map { SelectChoice(id: $0.name, label: $0.name, detail: $0.note, enabled: $0.available) },
            choose: { name in
                model.agent = name
                Task { await model.loadOptions() }
            }
        )
    }

    private func send() {
        Task { if let id = await model.send() { opened(id) } }
    }
}

/// The round mark over the question: a placeholder until the app has a logo to put in its place.
private struct NewSessionMark: View {
    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 22, weight: .medium)).foregroundStyle(.white)
            .frame(width: 52, height: 52)
            .background(Circle().fill(LinearGradient(colors: [.accentColor, .accentColor.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)))
            .accessibilityHidden(true)
    }
}
