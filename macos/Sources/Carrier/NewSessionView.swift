import AppKit
import CarrierCore
import SwiftUI

/// The draft of a new session in the centre (chat-ui-where2.html): the question, the sentence that says where it works, and the box
/// with the workspace chip, the agent chip and Send. Sending opens the session and `opened` selects it.
struct NewSessionView: View {
    @Bindable var model: NewSessionModel
    let opened: (String) -> Void
    @State private var foldersOpen = false
    @FocusState private var boxFocused: Bool

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            Text("What do you want to work on?").font(.title2.weight(.semibold))
            VStack(alignment: .leading, spacing: 8) {
                Text(model.sentence).font(.callout).foregroundStyle(.secondary).padding(.leading, 4)
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
                Button { model.choose(folder: folder.path); foldersOpen = false } label: {
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
        if panel.runModal() == .OK, let url = panel.url { model.choose(folder: url.path) }
    }

    private func send() {
        Task { if let id = await model.send() { opened(id) } }
    }
}
