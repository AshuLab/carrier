import CarrierCore
import CarrierUI
import SwiftUI

/// The round glass button in a session's header that counts its background processes: the prompt glyph and the count. It is grey and still, with no
/// arc, glow or dot, because nothing here is asked of the person and nothing in it should read as the model working. It is drawn only with a process.
struct ProcessesButton: View {
    let card: ProcessesCard
    /// Whether the list popover is open.
    var open = false
    let action: () -> Void

    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: Tokens.Space.s5) {
                Glyph(.terminal, size: 12)
                Text("\(card.processes.count)").scaledFont(12, weight: .medium).monospacedDigit()
            }
            .padding(.horizontal, Tokens.Space.s10)
            .frame(height: ToolbarPillButton.height)
            .background(Capsule().fill(Color.primary.opacity((hovered || open) && enabled ? 0.1 : 0)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .opacity(enabled ? 1 : 0.5)
        .animation(.easeOut(duration: 0.12), value: hovered)
        .glassEffect(.regular, in: .capsule)
        .help(card.title)
        .accessibilityLabel(card.title)
    }
}

/// The list opened by the Processes button: a row for each process (its name in monospace, cut in the middle because the end of a command is what
/// tells two apart, how long it has run from when the host first saw it, and its own Stop) and, with more than one, Stop all at the foot. A host
/// that does not list `stopTask` gets the rows with no Stop at all.
struct ProcessesListPopover: View {
    let card: ProcessesCard
    let stopAll: () -> Void
    let stopOne: (String) -> Void

    static let width: CGFloat = 440
    private static let rowHeight: CGFloat = 30
    private static let maxHeight: CGFloat = 320
    @Environment(\.windowSize) private var windowSize

    private var height: CGFloat {
        let foot = card.processes.count > 1 && card.stop != nil ? Self.rowHeight + Tokens.Space.s4 : 0
        // never taller than the window allows, as the Subagents list is
        return min(CGFloat(card.processes.count) * Self.rowHeight + foot + Tokens.Space.s8 * 2, Self.maxHeight, max(120, windowSize.height - 120))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.none) {
                ForEach(card.processes, id: \.id) { process in
                    row(process)
                }
                if card.processes.count > 1, let stop = card.stop {
                    HStack {
                        Spacer()
                        Button(stop, action: stopAll).buttonStyle(NoticeActionStyle()).help(card.stopHelp ?? "").accessibilityLabel(card.stopHelp ?? stop)
                    }
                    .padding(.top, Tokens.Space.s4)
                    .padding(.horizontal, Tokens.Space.s10)
                }
            }
            .padding(Tokens.Space.s8)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: Self.width, height: height)
        .accessibilityLabel(card.title)
    }

    private func row(_ process: CarrierCore.BackgroundTask) -> some View {
        HStack(spacing: Tokens.Space.s10) {
            Text(process.name).scaledFont(11.5, design: .monospaced).lineLimit(1).truncationMode(.middle).help(process.name)
            Spacer(minLength: Tokens.Space.s8)
            if let started = process.startedAt {
                TickingTimeline(every: 1) { context in
                    Text(workingElapsed(Int(context.date.timeIntervalSince(started)))).scaledFont(11.5).monospacedDigit().foregroundStyle(.secondary)
                }
                .fixedSize()
            }
            if card.stopsEach {
                Button(Copy.chatStop()) { stopOne(process.id) }.buttonStyle(NoticeActionStyle(quiet: true))
                    .help(Copy.chatStopTask(name: process.name)).accessibilityLabel(Copy.chatStopTask(name: process.name))
            }
        }
        .padding(.horizontal, Tokens.Space.s10)
        .frame(height: Self.rowHeight)
        .accessibilityElement(children: .contain)
    }
}
