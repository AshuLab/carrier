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
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.1)))
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

private struct CallDetailView: View {
    let call: ToolCall
    @State private var showAll = false
    @AppStorage(AppPreferences.outputLengthKey) private var length = AppPreferences.defaultOutputLength
    @AppStorage(AppPreferences.diffStyleKey) private var diffStyle = AppPreferences.defaultDiffStyle

    var body: some View {
        if call.diff.isEmpty == false {
            DiffView(rows: call.diff, showAll: $showAll, style: diffStyle).clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            let shown = length.visible(call.output, expanded: showAll)
            Console {
                if call.output.isEmpty {
                    Text(call.status == .running ? "running…" : "no output").foregroundStyle(ConsoleColor.text.opacity(0.6)).padding(.horizontal, 14)
                } else {
                    MonoLines(lines: shown.lines).foregroundStyle(ConsoleColor.text).textSelection(.enabled).padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if shown.hidden > 0 || showAll {
                        Button(showAll ? "Show less" : "Show \(shown.hidden) more \(shown.hidden == 1 ? "line" : "lines")") { showAll.toggle() }
                            .buttonStyle(.plain).font(.scaled(11)).foregroundStyle(Color.themeAccent)
                            .padding(.horizontal, 14).padding(.top, 7).padding(.bottom, 1)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
