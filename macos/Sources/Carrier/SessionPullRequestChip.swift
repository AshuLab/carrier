import AppKit
import CarrierCore
import SwiftUI

/// A session's pull request in its row: its number and how it stands, tinted by its state (`SessionPullRequest.tone`). A click opens it on GitHub.
struct SessionPullRequestChip: View {
    let pr: SessionPullRequest

    /// The purple GitHub gives a merged pull request.
    private static let merged = Color(red: 0.72, green: 0.42, blue: 0.95)

    private var tint: Color {
        switch pr.tone {
        case .open: SessionRowView.done
        case .failing: .red
        case .merged: Self.merged
        case .quiet: .secondary
        }
    }

    var body: some View {
        Button {
            // only a web address opens: what the host says of a pull request is not a command
            if let url = browserURL(pr.url) { NSWorkspace.shared.open(url) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.pull").font(.scaled(9, weight: .semibold))
                Text(pr.chipText).font(.scaled(11, weight: .medium).monospacedDigit())
            }
            .foregroundStyle(tint).padding(.horizontal, 6).frame(height: 17)
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
        HStack(spacing: 4) {
            Text("+\(diff.added)").foregroundStyle(SessionRowView.done)
            Text("−\(diff.removed)").foregroundStyle(Color.red)
        }
        .font(.scaled(11).monospacedDigit()).lineLimit(1).fixedSize()
    }
}
