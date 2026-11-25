import CarrierCore
import CarrierUI
import SwiftUI

/// One thought: two lines of it, and the whole of it when the person taps.
struct ThoughtRowView: View {
    let key: String
    let thought: Thought
    @Binding var flipped: Set<String>

    var body: some View {
        let whole = flipped.contains(key)
        HStack(alignment: .top, spacing: Tokens.Space.s10) {
            Glyph(.sparkles, size: 8).foregroundStyle(Color.thought)
                .frame(width: 16, height: 16).background(Circle().fill(Color.thought.opacity(0.2)))
            // as tall as the icon at least, so the first line is level with it
            Text(thought.text).scaledFont(12.5).lineSpacing(2).foregroundStyle(.secondary).lineLimit(whole ? nil : 2).multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 16, alignment: .topLeading).textSelection(.enabled)
        }
        .padding(.vertical, Tokens.Space.s6)
        .contentShape(Rectangle())
        .onTapGesture { flip(key, in: $flipped) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Copy.chatThoughtSpoken(text: thought.text))
    }
}

/// One call: what, on what and a short result; a failed call is red. It opens to the diff of a change or the provider's output.
struct CallRowView: View {
    let key: String
    let call: ToolCall
    @Binding var flipped: Set<String>
    @AppStorage(Preference.chatToolOutput) private var mode
    @AppStorage(Preference.chatOpensFailedCalls) private var opensFailed

    var body: some View {
        let open = call.opensByDefault(mode, opensFailed: opensFailed) != flipped.contains(key)
        VStack(alignment: .leading, spacing: Tokens.Space.none) {
            Button {
                flip(key, in: $flipped)
            } label: {
                HStack(spacing: Tokens.Space.s10) {
                    node
                    Text(call.label).fontWeight(.medium)
                    Text(call.subject).codeFont(12).lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if call.status != .running {
                        StateMark(shape: call.status.shape, size: 11, weight: .semibold).foregroundStyle(.red)
                        Text(call.result()).foregroundStyle(call.status == .failed ? .red : .secondary)
                    }
                    LogChevron(open: open)
                }
                .scaledFont(12)
                .foregroundStyle(call.status == .failed ? .red : .primary)
                .padding(.trailing, Tokens.Space.s6).frame(height: 26)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Copy.chatCallSpoken(label: call.label, subject: call.subject, result: call.result().isEmpty ? Copy.chatCallRunning() : call.result()))
            .accessibilityHint(open ? Copy.chatCallHintHide() : Copy.chatCallHintShow())
            if open { CallDetailView(call: call).padding(.leading, Tokens.Space.s24).padding(.top, Tokens.Space.s6).padding(.bottom, Tokens.Space.s6) }
        }
    }

    /// The call's node on the rail: its kind, a ring while it goes, red when it failed.
    @ViewBuilder private var node: some View {
        ZStack {
            Circle().fill(call.status == .failed ? Color.red.opacity(0.18) : Color.primary.opacity(0.09))
            if call.status == .running {
                SpinningRing(diameter: 9, lineWidth: 1.3, color: .secondaryLabelColor)
            } else {
                Glyph(call.kind.icon, size: 8).foregroundStyle(call.status == .failed ? Color.red : .secondary)
            }
        }
        .frame(width: 16, height: 16)
    }
}

/// What a call opens to: a change as its diff, anything else as the command (when it does not fit the row) and the output, each in the
/// code block of the messages, folded where the Output length setting says.
struct CallDetailView: View {
    let call: ToolCall
    @State private var showAll = false
    @AppStorage(Preference.chatOutputLength) private var lines
    @AppStorage(Preference.chatDiffStyle) private var diffStyle

    var body: some View {
        if call.diff.isEmpty == false {
            DiffView(rows: call.diff, showAll: $showAll, style: diffStyle).clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.control))
        } else {
            VStack(alignment: .leading, spacing: Tokens.Space.s10) {
                // the row cuts a long or multi-line command in the middle: opened, the call shows all of it
                if call.kind == .shell, call.arg.contains("\n") || call.arg.count > 80 { CodeBlockView(language: "bash", code: call.arg) }
                if case .mcp = call.kind, call.arg.isEmpty == false {
                    CodeBlockView(language: resolvedCodeLanguage(nil, code: call.arg) ?? Copy.chatCodeArguments(), code: call.arg)
                }
                if call.output.isEmpty {
                    Text(call.status == .running ? Copy.chatCallRunningDots() : Copy.chatCallNoOutput()).scaledFont(11.5).foregroundStyle(.secondary).padding(.horizontal, Tokens.Space.s6)
                } else {
                    CodeBlockView(language: Copy.chatCodeOutput(), code: call.output.joined(separator: "\n"), foldAfter: OutputLength(rawValue: lines)?.rawValue ?? AppPreferences.defaultOutputLength.rawValue, spare: 0)
                }
            }
        }
    }
}
