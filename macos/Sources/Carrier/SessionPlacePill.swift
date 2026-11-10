import AppKit
import CarrierCore
import SwiftUI

/// Where an open session works, in the toolbar, as a quiet indicator in the color of the person's accent: the branch for a worktree (a copy
/// of the project) and the folder itself otherwise. It says nothing more, so it does not call for attention. The tooltip has the full path,
/// and its context menu reveals the folder in Finder and copies its path or its branch name.
struct SessionPlacePill: View {
    let row: SessionRow

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: row.branch == nil ? "folder" : "arrow.triangle.branch").foregroundStyle(Color.themeAccent)
            if let branch = row.branch {
                Text("Worktree").fontWeight(.medium)
                Text(branch).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
            } else {
                Text("In the folder").fontWeight(.medium)
            }
        }
        .font(.caption).foregroundStyle(.secondary)
        .padding(.horizontal, 9).frame(height: 24)
        .background(Capsule().fill(Color.themeAccent.opacity(0.12)))
        .frame(maxWidth: 300)
        .help(row.branch == nil ? "Works in \(row.folder) itself" : "Works in a worktree of \(row.workspace): \(row.folder)")
        .contextMenu {
            ForEach(openMenuItems(row), id: \.title) { item in Button(item.title) { run(item) } }
        }
        .accessibilityElement(children: .combine)
    }

    private func run(_ item: OpenItem) {
        switch item.action {
        case .reveal(let path):
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        case .copy(let text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }
}
