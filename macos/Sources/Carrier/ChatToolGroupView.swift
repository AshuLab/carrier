import CarrierCore
import SwiftUI

/// A run of tool calls as one row (docs/specs/sessions-in-the-app.md, "The conversation: tools grouped"): the title and the summary,
/// red when a call failed, the line totals and the time. It opens to a line per call and a call opens to its detail; each is open or
/// folded by what the person chose for the tools (Settings, Chat) until the person flips it, which `flipped` remembers by id so a row
/// the lazy feed recycles keeps its state.
struct ChatToolGroupView: View {
    let id: String
    let group: ToolGroup
    @Binding var flipped: Set<String>
    @AppStorage(AppPreferences.toolOutputKey) private var mode = AppPreferences.defaultToolOutput
    @AppStorage(AppPreferences.opensFailedCallsKey) private var opensFailed = AppPreferences.defaultOpensFailedCalls
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let open = group.opensByDefault(mode, opensFailed: opensFailed) != flipped.contains(id)
        VStack(alignment: .leading, spacing: 0) {
            Button { toggle(id) } label: { header(open: open) }
                .buttonStyle(.plain)
                .accessibilityLabel("\(group.title), \(group.summary)\(group.failed > 0 ? ", \(group.failed) failed" : "")")
                .accessibilityHint(open ? "Hides its calls" : "Shows its calls")
            if open {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(group.calls) { call in CallRowView(key: "\(id)/\(call.id)", call: call, flipped: $flipped) }
                }
                .padding(.leading, 14).padding(.top, 2)
            }
        }
    }

    private func header(open: Bool) -> some View {
        HStack(spacing: 8) {
            LogChevron(open: open)
            Text(group.title).font(.scaled(12.5, weight: .semibold))
            Text(group.summary).font(.scaled(12.5)).foregroundStyle(.secondary).lineLimit(1)
            if group.failed > 0 {
                HStack(spacing: 4) {
                    StateMark(shape: .problem, size: 12)
                    Text("\(group.failed) failed").font(.scaled(12.5))
                }
                .foregroundStyle(.red)
            }
            Spacer(minLength: 8)
            if group.isWorking {
                SpinningRing(diameter: 11, lineWidth: 1.5, color: .secondaryLabelColor).overlay { StateMark(shape: .working, size: 6).foregroundStyle(.secondary) }
                Text(group.doing.map { "\($0)…" } ?? "").font(.scaled(12)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(formatCallDuration(max(0, Int(context.date.timeIntervalSince1970 * 1000) - group.startedAt)))
                        .font(.scaled(12)).monospacedDigit().foregroundStyle(.tertiary)
                }
            } else {
                if group.added > 0 { Text("+\(group.added)").foregroundStyle(.green) }
                if group.removed > 0 { Text("−\(group.removed)").foregroundStyle(.red) }
                if let ms = group.durationMs { Text(formatCallDuration(ms)).foregroundStyle(.tertiary) }
            }
        }
        .font(.scaled(12, weight: .medium)).monospacedDigit()
        .padding(.horizontal, 10).frame(height: 30)
        // the glass, tint and header fill of the code blocks, so the header and what it opens to are one family
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.045)))
        .glassEffect(.regular.tint(scheme == .dark ? Color.black.opacity(0.3) : nil), in: .rect(cornerRadius: 12))
        .contentShape(Rectangle())
    }

    private func toggle(_ key: String) {
        if flipped.insert(key).inserted == false { flipped.remove(key) }
    }
}

/// One call: what, on what and a short result; a failed call is red. It opens to the diff of a change or the provider's output.
private struct CallRowView: View {
    let key: String
    let call: ToolCall
    @Binding var flipped: Set<String>
    @AppStorage(AppPreferences.toolOutputKey) private var mode = AppPreferences.defaultToolOutput
    @AppStorage(AppPreferences.opensFailedCallsKey) private var opensFailed = AppPreferences.defaultOpensFailedCalls

    var body: some View {
        let open = call.opensByDefault(mode, opensFailed: opensFailed) != flipped.contains(key)
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if flipped.insert(key).inserted == false { flipped.remove(key) }
            } label: {
                HStack(spacing: 8) {
                    LogChevron(open: open)
                    Image(systemName: call.kind.icon).font(.scaled(11)).frame(width: 16)
                    Text(call.tool).fontWeight(.medium)
                    Text(call.arg).codeFont(12).lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if call.status == .running {
                        SpinningRing(diameter: 11, lineWidth: 1.5, color: .secondaryLabelColor).overlay { StateMark(shape: .working, size: 6).foregroundStyle(.secondary) }
                    } else {
                        StateMark(shape: call.status.shape, size: 11, weight: .semibold).foregroundStyle(.red)
                        Text(call.result).foregroundStyle(call.status == .failed ? .red : .secondary)
                    }
                }
                .font(.scaled(12))
                .foregroundStyle(call.status == .failed ? .red : .primary)
                .padding(.horizontal, 6).frame(height: 26)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(call.tool) \(call.arg), \(call.result.isEmpty ? "running" : call.result)")
            .accessibilityHint(open ? "Hides the detail" : "Shows the detail")
            if open { CallDetailView(call: call).padding(.leading, 20).padding(.bottom, 6) }
        }
    }
}

/// What a call opens to: a change as its diff, anything else as the command (when it does not fit the row) and the output, each in the
/// code block of the messages, folded where the Output length setting says.
private struct CallDetailView: View {
    let call: ToolCall
    @State private var showAll = false
    @AppStorage(AppPreferences.outputLengthKey) private var length = AppPreferences.defaultOutputLength
    @AppStorage(AppPreferences.diffStyleKey) private var diffStyle = AppPreferences.defaultDiffStyle

    var body: some View {
        if call.diff.isEmpty == false {
            DiffView(rows: call.diff, showAll: $showAll, style: diffStyle).clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            VStack(alignment: .leading, spacing: 6) {
                // the row cuts a long or multi-line command in the middle: opened, the call shows all of it
                if call.kind == .shell, call.arg.contains("\n") || call.arg.count > 80 { CodeBlockView(language: "bash", code: call.arg) }
                if call.output.isEmpty {
                    Text(call.status == .running ? "running…" : "no output").font(.scaled(11.5)).foregroundStyle(.secondary).padding(.horizontal, 6)
                } else {
                    CodeBlockView(language: "Output", code: call.output.joined(separator: "\n"), foldAfter: length.rawValue, spare: 0)
                }
            }
        }
    }
}
