import SwiftUI

/// The message box of the draft and of an open session: a roomy text area with a hint and the send button, which is Stop while the
/// agent answers, and under it the selects of what the session runs with. Enter sends and Shift+Enter adds a line.
struct MessageBox<Selects: View>: View {
    @Binding var text: String
    var placeholder: String
    var minLines = 3
    var canSend: Bool
    var sendHelp = "Send"
    /// Whether the agent is answering: the button is Stop, and Enter still sends (the session holds the message until the turn ends).
    var busy = false
    var focus: FocusState<Bool>.Binding
    /// Whether the selects get a darker, feathered patch behind them as wide as they are: over a conversation that scrolls under them.
    var halo = false
    var send: () -> Void
    var stop: () -> Void = {}
    @ViewBuilder var selects: () -> Selects
    /// Counts the sends, so the arrow bounces up each time one goes.
    @State private var sent = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 14)).lineLimit(minLines...10).focused(focus).focusEffectDisabled()
                    .onKeyPress(.return, phases: .down) { press in
                        if press.modifiers.contains(.shift) { text += "\n" } else { fire() }
                        return .handled
                    }
                HStack {
                    Spacer(minLength: 0)
                    button
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)
            // glass: the conversation that scrolls under the box is blurred, not seen through it
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
            // what the session runs with, under the box and at its left, side by side at their own width; a row that wraps when a provider
            // lists more than fit
            FlowLayout(spacing: 8) { selects() }
                .padding(.leading, 4)
                .background {
                    // as wide as the selects and no wider, with soft edges: the text that scrolls under them goes dark, not the whole row
                    if halo {
                        RoundedRectangle(cornerRadius: 16).fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
                            .padding(-8).blur(radius: 7)
                    }
                }
        }
    }

    /// Enter and the button: sends, and makes the arrow bounce when there is something to send.
    private func fire() {
        if canSend || busy { sent += 1 }
        send()
    }

    /// Glass, tinted when there is something to send and plain when there is not; it gives under the finger and springs back. The
    /// arrow becomes the Stop square while the agent answers, bounces up on a send and pulses while it works.
    private var button: some View {
        let active = canSend || busy
        let glass: Glass = active ? .regular.tint(.accentColor).interactive() : .regular
        return Button(action: busy ? stop : fire) {
            Image(systemName: busy ? "stop.fill" : "arrow.up")
                .font(.system(size: busy ? 12 : 14, weight: .bold)).foregroundStyle(active ? .white : .secondary)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce.up, value: sent)
                .symbolEffect(.pulse, isActive: busy)
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain).disabled(active == false)
        .glassEffect(glass, in: .circle)
        .animation(.smooth(duration: 0.25), value: active)
        .help(busy ? "Stop" : "\(sendHelp) (↩) · New line (⇧↩)").accessibilityLabel(busy ? "Stop" : "Send")
    }
}
