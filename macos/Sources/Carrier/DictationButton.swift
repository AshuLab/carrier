import CarrierCore
import SwiftUI

/// The microphone of the message box: a plain `mic` in a 36 point frame, no shape until the pointer is over it, then the round hover of
/// Send's size. A spinner takes its place while the dictation gets ready or transcribes.
struct DictationButton: View {
    let presentation: DictationPresentation
    /// The voice's level, `0...1`: the microphone fills from the bottom with it while it listens.
    var level: Float = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) { EmptyView() }
            .buttonStyle(DictationButtonStyle(presentation: presentation, level: level))
            .disabled(presentation.pressable == false)
            .help(presentation.help)
            .accessibilityLabel(presentation.label)
    }
}

private struct DictationButtonStyle: ButtonStyle {
    let presentation: DictationPresentation
    let level: Float

    func makeBody(configuration: Configuration) -> some View { Face(presentation: presentation, level: level, pressed: configuration.isPressed) }

    struct Face: View {
        let presentation: DictationPresentation
        let level: Float
        let pressed: Bool
        @State private var hovering = false
        /// How dim the solid microphone is under the level's fill while it listens.
        private static let listeningBase = 0.4

        var body: some View {
            let lit = (hovering || pressed) && presentation.pressable
            ZStack {
                switch presentation.icon {
                case .mic, .micSlash:
                    // listening is not told by the accent alone (a pale or gray accent reads weakly): the glyph turns from an outline to a dim solid
                    Image(systemName: presentation.icon == .micSlash ? "mic.slash" : presentation.inAccent ? "mic.fill" : "mic").font(.scaled(16))
                        .foregroundStyle(presentation.inAccent ? Color.themeAccent : lit ? Color.primary : Color.secondary)
                        .opacity(presentation.inAccent ? Self.listeningBase : 1)
                        .overlay {
                            // the capsule fills from the bottom with the level, like the Mac's own Dictation
                            if presentation.inAccent {
                                Image(systemName: "mic.fill").font(.scaled(16)).foregroundStyle(Color.themeAccent)
                                    .mask { Rectangle().scaleEffect(y: CGFloat(level), anchor: .bottom) }
                            }
                        }
                case .spinner:
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: 36, height: 36)
            .background(Circle().fill(Color.secondary.opacity(pressed ? 0.2 : hovering ? 0.14 : 0)))
            .contentShape(Circle())
            // the focus ring the other buttons have, round like the hover
            .contentShape(.focusEffect, Circle())
            .onHover { hovering = $0 }
        }
    }
}
