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
                            GitHubMark.image.renderingMode(.template).resizable().scaledToFit().frame(width: 14, height: 14)
                                .foregroundStyle(.secondary)
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

/// The GitHub mark (Octicons, MIT). SF Symbols has none; the system draws SVG data as a template image so it takes the text colour.
enum GitHubMark {
    static let image: Image = {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"/></svg>
        """
        guard let mark = NSImage(data: Data(svg.utf8)) else { return Image(systemName: "chevron.left.forwardslash.chevron.right") }
        return Image(nsImage: mark)
    }()
}
