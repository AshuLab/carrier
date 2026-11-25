import AppKit
import CarrierCore
import SwiftUI

/// Where an open session works, in the toolbar, as a quiet indicator in the color of the person's accent: the branch for a worktree (a copy
/// of the project) and the folder itself otherwise. It says nothing more, so it does not call for attention. The tooltip has the full path,
/// and its context menu reveals the folder in Finder and copies its path or its branch name.
struct SessionPlacePill: View {
    let row: SessionRow

    var body: some View {
        HStack(spacing: Tokens.Space.s5) {
            Glyph(row.branch == nil ? .folder : .gitBranch).foregroundStyle(.tint)
            if let branch = row.branch {
                Text(branch).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
            } else {
                Text(Copy.sessionPlaceInFolder()).fontWeight(.medium)
            }
        }
        .font(.caption).foregroundStyle(.secondary)
        .padding(.horizontal, Tokens.Space.s10).frame(height: 24)
        .background(Capsule().fill(.tint.opacity(0.12)))
        .frame(maxWidth: 300)
        // the toolbar item has no glass of its own, so nothing insets it from the window's rounded corner: match the gap above it
        .padding(.trailing, Tokens.Space.s6)
        .help(row.branch == nil ? Copy.sessionPlaceFolderHelp(folder: row.folder) : Copy.sessionPlaceBranchHelp())
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
