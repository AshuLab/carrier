import AppKit
import CarrierCore
import SwiftUI

/// The draft of a new session in the centre (chat-ui-where2.html): the question, the sentence that says where it works (the workspace,
/// then a new worktree or the current folder), and the box with the agent chip and Send. Sending opens the session and `opened` selects it.
struct NewSessionView: View {
    @Bindable var model: NewSessionModel
    let opened: (String) -> Void
    @State private var foldersOpen = false
    @State private var branchesOpen = false
    @State private var branchQuery = ""
    @FocusState private var boxFocused: Bool

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            NewSessionMark()
            VStack(spacing: 4) {
                Text("What do you want to work on?").font(.title2.weight(.semibold))
                Text("Pick where it works, then write.").font(.callout).foregroundStyle(.secondary)
            }
            .padding(.bottom, 10)
            VStack(alignment: .leading, spacing: 8) {
                sentence
                box
                if model.worktree, let branch = model.startBranch {
                    Text("Creates a worktree on the new branch \(worktreeBranchPrefix)\(model.worktreeName) from \(branch). The base folder stays as it is.")
                        .font(.caption).foregroundStyle(.secondary).padding(.leading, 4)
                }
                if let refusal = model.refusal {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(refusal).foregroundStyle(.red).textSelection(.enabled)
                        if let hint = signInLine(refusal: refusal) { Text(hint).foregroundStyle(.secondary) }
                    }
                    .font(.callout).padding(.leading, 4)
                }
            }
            .frame(maxWidth: 640)
            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // nothing scrolls under the toolbar here, so it takes the page's own colour and not the system's band
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .task { await model.load() }
        .onAppear { boxFocused = true }
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
                .popover(isPresented: $foldersOpen, arrowEdge: .bottom) { picker }
                if let repo = model.cloning {
                    ProgressView().controlSize(.small)
                    Text("Cloning \(repo)…")
                }
                if model.folder != nil {
                    if model.offersWorktree {
                        Text("on")
                        Menu {
                            Button { Task { await model.useWorktree(false) } } label: { Label("Current folder", systemImage: model.worktree ? "" : "checkmark") }
                            Button { Task { await model.useWorktree(true) } } label: { Label("New worktree", systemImage: model.worktree ? "checkmark" : "") }
                        } label: {
                            chip(model.worktree ? "New worktree" : "Current folder")
                        }
                        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                        .accessibilityLabel("Where it works")
                        if model.worktree { worktreeControls } else { Text("(\(model.workspace?.branch ?? "detached HEAD"))") }
                    } else {
                        Text(rest)
                    }
                }
            }
            .font(.callout).foregroundStyle(.secondary).padding(.leading, 4)
            .accessibilityElement(children: .contain)
            if let note = model.watchNote {
                Text(note).font(.callout).foregroundStyle(model.watchFailed ? .orange : .secondary).padding(.leading, 4).textSelection(.enabled)
            }
            if let warning = model.warning { Text(warning).font(.callout).foregroundStyle(.orange).padding(.leading, 4) }
            if case .problem(let reason) = model.nameState, model.worktree {
                Text(reason).font(.callout).foregroundStyle(.red).padding(.leading, 4).textSelection(.enabled)
            }
            if let problem = model.workspaceProblem { Text(problem).font(.callout).foregroundStyle(.red).padding(.leading, 4).textSelection(.enabled) }
        }
    }

    /// What `model.sentence` says after "Work in <workspace> ".
    private var rest: String {
        let head = "Work in \(model.folder.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "") "
        return model.sentence.hasPrefix(head) ? String(model.sentence.dropFirst(head.count)) : model.sentence
    }

    /// A control of the sentence: its value and a chevron, on a faint fill.
    private func chip(_ title: String, tint: Color = .primary) -> some View {
        HStack(spacing: 4) {
            Text(title).fontWeight(.medium)
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8).padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 6).fill(tint.opacity(0.14)))
        .contentShape(Rectangle())
    }

    /// The fixed `carrier/` prefix, the name (typed over in place) with ↻, and the branch it starts from.
    @ViewBuilder private var worktreeControls: some View {
        HStack(spacing: 4) {
            Text(worktreeBranchPrefix).foregroundStyle(.tertiary)
            TextField("name", text: $model.worktreeName)
                .textFieldStyle(.plain).autocorrectionDisabled().fixedSize()
                .foregroundStyle(nameColor).accessibilityLabel("Worktree name")
            Button { Task { await model.rollName() } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain).help("Pick another name").accessibilityLabel("Suggest another name")
        }
        .font(.callout.monospaced())
        .padding(.horizontal, 8).padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(nameBorder, lineWidth: 1))
        // the name is checked a moment after typing; typing again cancels the check that was waiting
        .task(id: model.worktreeName) { await model.verifyName() }
        Text("from")
        Button { branchesOpen.toggle() } label: { chip(model.startBranch ?? "Choose a branch…") }
            .buttonStyle(.plain)
            .popover(isPresented: $branchesOpen, arrowEdge: .bottom) { branches }
    }

    private var nameColor: Color {
        if case .problem = model.nameState { .red } else { .primary }
    }

    private var nameBorder: Color {
        if case .problem = model.nameState { .red } else { .clear }
    }

    /// The branch picker: a search, the local and the remote branches in two sections, and Fetch now with when it last did.
    private var branches: some View {
        let picker = model.picker(query: branchQuery)
        return VStack(alignment: .leading, spacing: 6) {
            TextField("Search branches", text: $branchQuery).textFieldStyle(.roundedBorder)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    branchSection("Local", picker?.local ?? [])
                    branchSection("Remote", picker?.remote ?? [])
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 220)
            Divider()
            HStack {
                Text(picker?.fetched ?? "").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button(model.fetching ? "Fetching…" : "Fetch now") { Task { await model.fetchNow() } }
                    .controlSize(.small).disabled(model.fetching)
            }
            if let problem = model.fetchProblem { Text(problem).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
        }
        .padding(10).frame(width: 300)
    }

    @ViewBuilder private func branchSection(_ title: String, _ rows: [BranchRow]) -> some View {
        if rows.isEmpty == false {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 4)
            ForEach(rows, id: \.name) { row in
                Button { model.choose(startBranch: row.name); branchesOpen = false } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark").opacity(model.startBranch == row.name ? 1 : 0).font(.caption)
                        Text(row.name).lineLimit(1).truncationMode(.middle)
                        if row.checkedOut { tag("checked out") }
                        if row.isDefault { tag("default") }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain).padding(.horizontal, 8).padding(.vertical, 3)
            }
        }
    }

    private func tag(_ text: String) -> some View {
        Text(text).font(.caption2).foregroundStyle(.secondary)
            .padding(.horizontal, 5).padding(.vertical, 1).background(Capsule().fill(Color.secondary.opacity(0.15)))
    }

    private var box: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Write the first message…", text: $model.text, axis: .vertical)
                .textFieldStyle(.plain).lineLimit(2...8).focused($boxFocused)
                // Enter sends and Shift+Enter adds a line
                .onKeyPress(.return, phases: .down) { press in
                    if press.modifiers.contains(.shift) { model.text += "\n" } else { send() }
                    return .handled
                }
            HStack(spacing: 8) {
                Menu {
                    ForEach(model.agents, id: \.name) { choice in
                        Button(choice.note.map { "\(choice.name) (\($0))" } ?? choice.name) { model.agent = choice.name }
                            .disabled(choice.available == false)
                    }
                } label: {
                    Label(model.agent ?? "Agent", systemImage: "sparkle")
                }
                .menuStyle(.button).buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.small).fixedSize()
                Spacer(minLength: 0)
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 26, height: 26).background(Circle().fill(Color.accentColor.opacity(model.canSend ? 1 : 0.35)))
                }
                .buttonStyle(.plain).disabled(model.canSend == false).help(model.canSend ? "Send" : "Choose a workspace and write a message")
                .accessibilityLabel("Send")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.secondary.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.secondary.opacity(0.25), lineWidth: 0.5))
        // nothing to write to until a workspace is chosen
        .opacity(model.folder == nil ? 0.5 : 1)
    }

    /// The workspace popover: the menu, or the step of a source inside it.
    @ViewBuilder private var picker: some View {
        switch model.step {
        case .menu: menu
        case .url: urlStep
        case .project: projectStep
        }
    }

    /// Recent folders, the projects folder's, the sources and a footer with where the projects folder is.
    private var menu: some View {
        VStack(alignment: .leading, spacing: 2) {
            menuHeader("Recent")
            ForEach(model.recent, id: \.path) { folder in folderRow(folder.name, folder.path) }
            if model.recent.isEmpty { Text("No recent folders").foregroundStyle(.secondary).padding(8) }
            if model.projects.isEmpty == false {
                menuHeader("In your projects folder")
                ForEach(model.projects, id: \.path) { folderRow($0.name, $0.path) }
            }
            Divider().padding(.vertical, 4)
            ForEach(model.sources, id: \.self) { source in
                switch source {
                case .localFolder:
                    sourceRow(source.rawValue, "folder.badge.plus", drills: false) { openFolder() }
                case .githubURL:
                    sourceRow(source.rawValue, "link", drills: true) { model.show(.url) }
                case .newProject:
                    sourceRow(source.rawValue, "folder.badge.gearshape", drills: true) { model.show(.project) }
                }
            }
            Divider().padding(.vertical, 4)
            HStack(spacing: 4) {
                Text("Projects folder").foregroundStyle(.secondary)
                Text((model.projectsPath as NSString).abbreviatingWithTildeInPath).font(.caption.monospaced()).lineLimit(1).truncationMode(.head)
                Spacer(minLength: 0)
                Button("Change…") { changeProjectsFolder() }.buttonStyle(.link)
            }
            .font(.caption).padding(.horizontal, 8).padding(.vertical, 2)
            if let problem = model.projectsFolderProblem {
                Text(problem).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 8)
            }
        }
        .padding(8).frame(width: 340)
    }

    private func menuHeader(_ title: String) -> some View {
        Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.top, 4)
    }

    private func folderRow(_ name: String, _ path: String) -> some View {
        Button { foldersOpen = false; Task { await model.choose(folder: path) } } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                Text((path as NSString).abbreviatingWithTildeInPath).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            }
            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain).padding(.horizontal, 8).padding(.vertical, 4)
    }

    private func sourceRow(_ title: String, _ icon: String, drills: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: icon)
                Spacer(minLength: 0)
                if drills { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain).padding(.horizontal, 8).padding(.vertical, 4)
    }

    /// From a GitHub URL: the text, what will happen to it, and the button; while it clones, the clone and Cancel.
    private var urlStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button { model.show(.menu) } label: { Label("Back", systemImage: "chevron.left") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).disabled(model.cloning != nil)
                Text("From a GitHub URL").fontWeight(.semibold)
            }
            TextField("owner/repo  or  https://github.com/owner/repo", text: $model.urlText)
                .textFieldStyle(.roundedBorder).autocorrectionDisabled().disabled(model.cloning != nil)
                .onSubmit { clone() }
            Toggle("Let Carrier watch this repo", isOn: Binding(get: { model.watching }, set: { model.watch = $0 }))
                .disabled(model.watchProblem != nil || model.cloning != nil)
            if let reason = model.watchProblem {
                Text(reason).font(.caption).foregroundStyle(.secondary)
            }
            if let repo = model.cloning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Cloning \(repo)…")
                }
                .font(.callout)
            } else if let problem = model.cloneProblem {
                Text(problem).font(.callout).foregroundStyle(.red).textSelection(.enabled)
            } else if model.alreadyThere {
                Text("Already in your projects folder. It will be updated (fetch) and opened, not cloned again.").font(.callout).foregroundStyle(.orange)
            }
            HStack {
                Spacer(minLength: 0)
                Button("Cancel") {
                    model.cancelClone()
                    foldersOpen = false
                }
                .keyboardShortcut(.cancelAction)
                if model.cloning == nil {
                    Button(model.cloneButton) { clone() }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(model.canCloneNow == false)
                }
            }
        }
        .padding(12).frame(width: 340)
    }

    /// New project: a name, the path it will make, and the button; no watch box, a new project has no GitHub repository.
    private var projectStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button { model.show(.menu) } label: { Label("Back", systemImage: "chevron.left") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).disabled(model.creating)
                Text("New project").fontWeight(.semibold)
            }
            TextField("Project name", text: $model.projectName)
                .textFieldStyle(.roundedBorder).autocorrectionDisabled().disabled(model.creating)
                .onSubmit { create() }
            Text("Will make \((model.projectPath as NSString).abbreviatingWithTildeInPath) and run git init on main.")
                .font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(2).truncationMode(.head)
            if let warning = model.projectNameWarning {
                Text(warning).font(.callout).foregroundStyle(.orange)
            } else if let problem = model.createProblem {
                Text(problem).font(.callout).foregroundStyle(.red).textSelection(.enabled)
            }
            HStack {
                Spacer(minLength: 0)
                Button("Cancel") { foldersOpen = false }.keyboardShortcut(.cancelAction)
                Button("Create and use") { create() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(model.canCreateNow == false)
            }
        }
        .padding(12).frame(width: 340)
    }

    private func create() {
        guard model.canCreateNow else { return }
        Task { if await model.createAndUse() { foldersOpen = false } }
    }

    private func clone() {
        guard model.canCloneNow else { return }
        Task { if await model.cloneAndUse() { foldersOpen = false } }
    }

    /// The footer's Change…: the folder panel, then the popover comes back to show the new path or why it was refused.
    private func changeProjectsFolder() {
        foldersOpen = false
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: model.projectsPath)
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { model.changeProjectsFolder(to: url.path) }
        foldersOpen = true
    }

    private func openFolder() {
        foldersOpen = false
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { Task { await model.choose(folder: url.path) } }
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
