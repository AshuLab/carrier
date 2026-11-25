import AppKit
import CarrierCore
import SwiftUI

/// A session's pull request in its row: its number and how it stands, tinted by its state (`SessionPullRequest.tone`). A click opens it on GitHub.
struct SessionPullRequestChip: View {
    let pr: SessionPullRequest

    private var tint: Color { pr.tint }

    var body: some View {
        Button {
            // only a web address opens: what the host says of a pull request is not a command
            if let url = browserURL(pr.url) { NSWorkspace.shared.open(url) }
        } label: {
            HStack(spacing: Tokens.Space.s4) {
                Glyph(.gitPullRequest, size: 9)
                Text(pr.chipText).scaledFont(11, weight: .medium).monospacedDigit()
            }
            .foregroundStyle(tint).padding(.horizontal, Tokens.Space.s6).frame(height: 17)
            .background(Capsule().fill(tint.opacity(0.16)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain).help("Open pull request #\(pr.number) on GitHub").accessibilityLabel(pr.spoken).accessibilityHint("Opens it on GitHub")
    }
}

/// The lines a session changed, as plain text: "+86 −12".
struct DiffText: View {
    let diff: SessionDiff

    var body: some View {
        HStack(spacing: Tokens.Space.s4) {
            Text("+\(diff.added)").foregroundStyle(Color.sessionDone)
            Text("−\(diff.removed)").foregroundStyle(Color.red)
        }
        .scaledFont(11).monospacedDigit().lineLimit(1).fixedSize()
    }
}

extension SessionPullRequest {
    /// The colour of its state: green open, red failing, the purple GitHub gives a merged one, grey for a draft or a closed one.
    var tint: Color {
        switch tone {
        case .open: Color.sessionDone
        case .failing: .red
        case .merged: Color(Tokens.PullRequest.merged)
        case .quiet: .secondary
        }
    }
}

/// The third line of a sidebar row: the pull request and the lines changed in one capsule. The capsule is always there, so nothing moves when it
/// shows its fill: none at rest, a quiet one under the pointer, a light one on the selected row, whose fill is already deep.
/// No colour but a dot for the state (hollow for a draft or a closed one); the words and the lines are grey.
struct SessionWorkPill: View {
    let pr: SessionPullRequest?
    let diff: SessionDiff?
    @Environment(\.rowState) private var state

    private var fill: Color {
        switch state {
        case .resting: .clear
        case .hovered: Color.primary.opacity(0.1)
        case .selected: Color.white.opacity(0.14)
        }
    }

    /// Grey, a little softer than white on the selected row so the pill does not shout.
    private var words: Color { state == .selected ? Color.white.opacity(0.72) : .secondary }

    var body: some View {
        if pr != nil || diff != nil {
            HStack(spacing: Tokens.Space.s6) {
                if let pr {
                    Button {
                        // only a web address opens: what the host says of a pull request is not a command
                        if let url = browserURL(pr.url) { NSWorkspace.shared.open(url) }
                    } label: {
                        HStack(spacing: Tokens.Space.s5) {
                            if pr.tone == .quiet {
                                Circle().strokeBorder(pr.tint, lineWidth: 1.3).frame(width: 6, height: 6)
                            } else {
                                Circle().fill(pr.tint).frame(width: 6, height: 6)
                            }
                            Text(pr.chipText)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).help("Open pull request #\(pr.number) on GitHub").accessibilityLabel(pr.spoken).accessibilityHint("Opens it on GitHub")
                }
                if pr != nil, diff != nil { Rectangle().frame(width: 1, height: 9).opacity(0.3) }
                if let diff { Text("+\(diff.added) −\(diff.removed)") }
            }
            .scaledFont(11, weight: .medium).monospacedDigit().foregroundStyle(words).lineLimit(1).fixedSize()
            .padding(.horizontal, Tokens.Space.s8).frame(height: 17)
            .background(Capsule().fill(fill))
            .animation(.easeOut(duration: 0.12), value: state)
        }
    }
}
