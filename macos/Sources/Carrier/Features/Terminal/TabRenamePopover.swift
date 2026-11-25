import AppKit
import CarrierCore
import SwiftUI
import UniformTypeIdentifiers

struct TabRenamePopover: View {
    @Binding var title: String
    let hasCustomTitle: Bool
    let save: () -> Void
    let reset: () -> Void
    let cancel: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s10) {
            Text("Rename Tab")
                .scaledFont(12, weight: .semibold)
            TextField("Tab name", text: $title)
                .settingsField(width: 248, focused: $focused)
                .onSubmit(save)
                .onKeyPress(.escape) {
                    cancel()
                    return .handled
                }
            HStack(spacing: Tokens.Space.s8) {
                if hasCustomTitle {
                    Button(action: reset) {
                        Label("Reset", icon: .rotate)
                    }
                    .buttonStyle(SecondaryCapsuleButtonStyle())
                    .controlSize(.small)
                }
                Spacer(minLength: 0)
                Button(action: cancel) {
                    Label("Cancel", icon: .close)
                }
                .buttonStyle(SecondaryCapsuleButtonStyle())
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)
                Button(action: save) {
                    Label("Save", icon: .check)
                }
                .buttonStyle(PrimaryCapsuleButtonStyle())
                .controlSize(.small)
            }
        }
        .padding(Tokens.Space.s12)
        .onAppear { focused = true }
    }
}
