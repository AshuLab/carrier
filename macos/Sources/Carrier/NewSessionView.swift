import AppKit
import CarrierCore
import SwiftUI

/// The draft of a new session in the centre (chat-ui-where2.html): the question, the sentence that says where it works, and the box
/// with the workspace chip, the agent chip and Send. Sending opens the session and `opened` selects it.
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
            Text("What do you want to work on?").font(.title2.weight(.semibold))
            VStack(alignment: .leading, spacing: 8) {
                sentence
                box
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
        .task { await model.load() }
        .onAppear { boxFocused = true }
    }

    /// "Work in <workspace> on the base folder (main)": in a git repository "base folder" is a control that switches to
    /// "in a new worktree carrier/<name> from <branch>"; the other cases are said in words, as `model.sentence` has them.
    @ViewBuilder private var sentence: some View {
        VStack(alignment: .leading, spacing: 4) {
            if model.offersWorktree, let folder = model.folder {
                FlowLayout(spacing: 4) {
                    Text("Work in \(URL(fileURLWithPath: folder).lastPathComponent)")
                    Menu(model.worktree ? "in a new worktree" : "on the base folder") {
                        Button("On the base folder") { Task { await model.useWorktree(false) } }
                        Button("In a new worktree") { Task { await model.useWorktree(true) } }
                    }
                    .menuStyle(.button).buttonStyle(.plain).foregroundStyle(Color.accentColor).fixedSize()
                    .accessibilityLabel("Where it works")
                    if model.worktree { worktreeControls } else { Text("(\(model.workspace?.branch ?? "detached HEAD"))") }
                }
                .font(.callout).foregroundStyle(.secondary).padding(.leading, 4)
                .accessibilityElement(children: .contain)
            } else {
                Text(model.sentence).font(.callout).foregroundStyle(.secondary).padding(.leading, 4)
            }
            if let warning = model.warning { Text(warning).font(.callout).foregroundStyle(.orange).padding(.leading, 4) }
            if case .problem(let reason) = model.nameState, model.worktree {
                Text(reason).font(.callout).foregroundStyle(.red).padding(.leading, 4).textSelection(.enabled)
            }
            if let problem = model.workspaceProblem { Text(problem).font(.callout).foregroundStyle(.red).padding(.leading, 4).textSelection(.enabled) }
        }
    }

    /// The fixed `carrier/` prefix, the editable rest of the name with ↻, and the branch it starts from.
    @ViewBuilder private var worktreeControls: some View {
        HStack(spacing: 2) {
            Text(worktreeBranchPrefix)
            TextField("name", text: $model.worktreeName)
                .textFieldStyle(.plain).autocorrectionDisabled().frame(minWidth: 120)
                .foregroundStyle(nameColor).accessibilityLabel("Worktree name")
            Button { Task { await model.rollName() } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain).help("Suggest another name").accessibilityLabel("Suggest another name")
        }
        .padding(.horizontal, 6).padding(.vertical, 1)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)))
        // the name is checked a moment after typing; typing again cancels the check that was waiting
        .task(id: model.worktreeName) { await model.verifyName() }
        Text("from")
        Button { branchesOpen.toggle() } label: { Label(model.startBranch ?? "Choose a branch…", systemImage: "arrow.triangle.branch") }
            .buttonStyle(.plain).foregroundStyle(Color.accentColor)
            .popover(isPresented: $branchesOpen, arrowEdge: .bottom) { branches }
    }

    private var nameColor: Color {
        if case .problem = model.nameState { .red } else { .primary }
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
            TextField("Message the agent", text: $model.text, axis: .vertical)
                .textFieldStyle(.plain).lineLimit(2...8).focused($boxFocused)
                // Enter sends and Shift+Enter adds a line
                .onKeyPress(.return, phases: .down) { press in
                    if press.modifiers.contains(.shift) { model.text += "\n" } else { send() }
                    return .handled
                }
            HStack(spacing: 8) {
                Button { foldersOpen.toggle() } label: {
                    Label(model.folder.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Choose a workspace…", systemImage: "folder")
                }
                .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.small)
                .popover(isPresented: $foldersOpen, arrowEdge: .bottom) { folders }
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
    }

    /// The recent folders with their paths, and Open folder… for the system's folder panel.
    private var folders: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(model.recent, id: \.path) { folder in
                Button { foldersOpen = false; Task { await model.choose(folder: folder.path) } } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(folder.name)
                        Text(folder.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain).padding(.horizontal, 8).padding(.vertical, 4)
            }
            if model.recent.isEmpty { Text("No recent folders").foregroundStyle(.secondary).padding(8) }
            Divider()
            Button { openFolder() } label: { Label("Open folder…", systemImage: "folder.badge.plus").frame(maxWidth: .infinity, alignment: .leading) }
                .buttonStyle(.plain).padding(.horizontal, 8).padding(.vertical, 4)
        }
        .padding(8).frame(width: 320)
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
