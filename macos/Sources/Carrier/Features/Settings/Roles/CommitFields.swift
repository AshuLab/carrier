import AppKit
import CarrierCore
import CarrierUI
import SwiftUI

/// A text saved when the person presses Return or leaves the field; what the file refuses is put back.
struct CommitField: View {
    let label: String
    let text: String
    let width: CGFloat
    let mono: Bool
    var prompt = ""
    let commit: (String) async -> Bool
    @State private var draft: String
    @FocusState private var focused: Bool

    init(label: String, text: String, width: CGFloat, mono: Bool, prompt: String = "", commit: @escaping (String) async -> Bool) {
        self.label = label
        self.text = text
        self.width = width
        self.mono = mono
        self.prompt = prompt
        self.commit = commit
        _draft = State(initialValue: text)
    }

    var body: some View {
        TextField(label, text: $draft, prompt: Text(prompt))
            .scaledFont(mono ? 11.5 : 13, design: mono ? .monospaced : nil).settingsField(width: width, focused: $focused)
            .onSubmit(save)
            .onChange(of: focused) { _, now in if now == false { save() } }
            .accessibilityLabel(label)
    }

    private func save() {
        guard draft != text else { return }
        let value = draft
        Task { if await commit(value) == false { draft = text } }
    }
}

/// A text of several lines saved when the person leaves it (a return is a new line here, so there is no key that saves); what the file refuses is
/// put back. In the box of `settingsField`, with the prompt shown while it is empty.
struct CommitEditor: View {
    let label: String
    let text: String
    var prompt = ""
    let commit: (String) async -> Bool
    @State private var draft: String
    @FocusState private var focused: Bool

    init(label: String, text: String, prompt: String = "", commit: @escaping (String) async -> Bool) {
        self.label = label
        self.text = text
        self.prompt = prompt
        self.commit = commit
        _draft = State(initialValue: text)
    }

    var body: some View {
        TextEditor(text: $draft).scaledFont(13).scrollContentBackground(.hidden).frame(height: 96)
            .overlay(alignment: .topLeading) {
                if draft.isEmpty { Text(prompt).foregroundStyle(.tertiary).padding(.leading, Tokens.Space.s5).allowsHitTesting(false) }
            }
            .settingsField(focused: $focused)
            // the system's writing tools (and its "Write with Siri" button, which sits on the box) have nothing to do with an instruction for an agent
            .writingToolsBehavior(.disabled)
            .onChange(of: focused) { _, now in if now == false { save() } }
            .accessibilityLabel(label)
    }

    private func save() {
        guard draft != text else { return }
        let value = draft
        Task { if await commit(value) == false { draft = text } }
    }
}
