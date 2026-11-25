import CarrierCore
import SwiftUI

/// A page's note as the toolbar shows it, at its right: why the Behavior page cannot save, with a way to ask Carrier again.
struct SettingsNoteView: View {
    let note: SettingsHeaderNote
    let pending: Bool
    let ask: () -> Void

    var body: some View {
        HStack(spacing: Tokens.Space.s10) {
            Group {
                switch note.tone {
                case .problem: Label(note.text, icon: .warningFilled).foregroundStyle(.orange)
                case .plain: Label(note.text, icon: .info).foregroundStyle(.secondary)
                }
            }
            .scaledFont(12).lineLimit(2).frame(maxWidth: 420, alignment: .trailing)
            if note.asksAgain { AskAgainButton(pending: pending, action: ask) }
        }
    }
}
