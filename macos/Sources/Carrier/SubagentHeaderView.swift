import CarrierCore
import SwiftUI

// The pieces of the window's header while a subagent view is open (the toolbar places them in `PanelView`): its title over the line that says
// whose it is, and its state in place of the worktree pill. The header is as high as the round glass buttons beside it, whatever the title:
// what does not fit is cut, never wrapped.

/// The subagent's description over "Explore · Subagent of <the session's title>".
struct SubagentTitle: View {
    /// As high as the round glass buttons of the toolbar.
    static let height: CGFloat = 34

    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.scaled(13, weight: .semibold)).lineLimit(1).truncationMode(.tail)
            Text(subtitle).font(.scaled(11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
        }
        .frame(height: Self.height, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Running with its timer, Finished with its duration, Failed or Stopped, as a quiet capsule like the worktree pill it replaces.
struct SubagentStatePill: View {
    let header: SubagentHeader
    /// The time the timer reads instead of the clock; a test sets it.
    var clock: Date?

    var body: some View {
        HStack(spacing: 6) {
            mark.frame(width: 10, height: 10)
            if header.state == .running {
                TimelineView(.periodic(from: .now, by: 1)) { context in words(Int((clock ?? context.date).timeIntervalSince1970 * 1000)) }
            } else {
                words(0)
            }
        }
        .font(.scaled(12, weight: .medium)).monospacedDigit().foregroundStyle(.secondary)
        .padding(.horizontal, 10).frame(height: 24)
        .background(Capsule().fill(Color.primary.opacity(0.08)))
        .padding(.trailing, 6)
        .accessibilityElement(children: .combine)
    }

    private func words(_ now: Int) -> some View { Text(header.stateWords(now: now)).lineLimit(1).fixedSize() }

    @ViewBuilder private var mark: some View {
        switch header.state {
        case .running: SpinningRing(diameter: 9, lineWidth: 1.5, color: .secondaryLabelColor)
        case .completed: Circle().fill(Color.green)
        case .failed: Circle().fill(Color.red)
        case .stopped: RoundedRectangle(cornerRadius: 1.5).fill(Color.secondary).padding(1)
        }
    }
}
