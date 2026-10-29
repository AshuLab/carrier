import SwiftUI

/// The message box of the draft and of an open session: a roomy text area, then the selects of what the session runs with, a hint
/// and the send button, which is Stop while the agent answers. Enter sends and Shift+Enter adds a line; the box shows its focus.
struct MessageBox<Selects: View>: View {
    @Binding var text: String
    var placeholder: String
    var minLines = 3
    var canSend: Bool
    var sendHelp = "Send"
    /// Whether the agent is answering: the button is Stop, and Enter still sends (the session holds the message until the turn ends).
    var busy = false
    var focus: FocusState<Bool>.Binding
    var send: () -> Void
    var stop: () -> Void = {}
    @ViewBuilder var selects: () -> Selects

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 14)).lineLimit(minLines...10).focused(focus)
                .onKeyPress(.return, phases: .down) { press in
                    if press.modifiers.contains(.shift) { text += "\n" } else { send() }
                    return .handled
                }
            HStack(spacing: 6) {
                selects()
                Spacer(minLength: 12)
                if text.isEmpty == false {
                    Text(busy ? "↩ sends it when the agent finishes" : "↩ send   ⇧↩ new line")
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1).layoutPriority(1)
                }
                button.layoutPriority(2)
            }
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(focus.wrappedValue ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.14), lineWidth: focus.wrappedValue ? 1.5 : 1))
        .animation(.easeOut(duration: 0.15), value: focus.wrappedValue)
    }

    private var button: some View {
        Button(action: busy ? stop : send) {
            Image(systemName: busy ? "stop.fill" : "arrow.up")
                .font(.system(size: busy ? 12 : 14, weight: .bold)).foregroundStyle(canSend || busy ? .white : .secondary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(canSend || busy ? Color.accentColor : Color.primary.opacity(0.12)))
        }
        .buttonStyle(.plain).disabled(canSend == false && busy == false)
        .help(busy ? "Stop" : sendHelp).accessibilityLabel(busy ? "Stop" : "Send")
    }
}
