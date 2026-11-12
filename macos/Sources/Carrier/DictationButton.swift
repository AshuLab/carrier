import CarrierCore
import SwiftUI

/// The microphone of the message box: a plain `mic` in a 36 point frame, no shape until the pointer is over it, then the round hover of
/// Send's size. A spinner takes its place while the dictation gets ready or transcribes.
struct DictationButton: View {
    let presentation: DictationPresentation
    let action: () -> Void

    var body: some View {
        Button(action: action) { EmptyView() }
            .buttonStyle(DictationButtonStyle(presentation: presentation))
            .disabled(presentation.pressable == false)
            .help(presentation.help)
            .accessibilityLabel(presentation.label)
    }
}

private struct DictationButtonStyle: ButtonStyle {
    let presentation: DictationPresentation

    func makeBody(configuration: Configuration) -> some View { Face(presentation: presentation, pressed: configuration.isPressed) }

    struct Face: View {
        let presentation: DictationPresentation
        let pressed: Bool
        @State private var hovering = false

        var body: some View {
            let lit = (hovering || pressed) && presentation.pressable
            ZStack {
                switch presentation.icon {
                case .mic:
                    Image(systemName: "mic").font(.scaled(16))
                        .foregroundStyle(presentation.inAccent ? Color.themeAccent : lit ? Color.primary : Color.secondary)
                case .spinner:
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: 36, height: 36)
            .background(Circle().fill(Color.secondary.opacity(pressed ? 0.2 : hovering ? 0.14 : 0)))
            .contentShape(Circle())
            .onHover { hovering = $0 }
        }
    }
}
