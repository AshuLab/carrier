import AppKit
import CarrierCore
import SwiftUI

/// The Overview's watched repositories; a thin mapping of `carrierBox(_:)`. What Carrier itself is doing is in the sidebar.
struct WatchedReposView: View {
    let snapshot: PanelSnapshot

    var body: some View {
        let box = carrierBox(snapshot)
        if box.repoCount > 0 {
            VStack(alignment: .leading, spacing: 8) {
                OverviewTitle(title: "Watched repositories", detail: "\(box.repoCount)")
                OverviewCard {
                    ForEach(box.repos, id: \.name) { repo in
                        OverviewLinkRow(action: { open(repo.url) }) {
                            Image(systemName: "arrow.triangle.branch").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(Color.secondary.opacity(0.15)))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(repo.name).fontWeight(.semibold)
                                Text(repo.url).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                if let error = repo.error { Text(error).font(.caption).foregroundStyle(.red) }
                            }
                            Spacer(minLength: 8)
                            RepoStatusPill(status: repo.status)
                            Text(repo.lastCheck).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func open(_ url: String) {
        if let target = URL(string: "https://" + url) { NSWorkspace.shared.open(target) }
    }
}

/// Whether a repository is being looked at: green while it is, grey while intake is paused, red when its last check failed.
private struct RepoStatusPill: View {
    let status: CarrierBox.Status

    var body: some View {
        let (text, color): (String, Color) = switch status {
        case .watching: ("Watching", .green)
        case .paused: ("Paused", .gray)
        case .failing: ("Failing", .red)
        }
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.18)))
    }
}
