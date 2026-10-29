import CarrierCore
import SwiftUI

/// The title bar of an open session: its name, and under it what it is working on, in words and marks: the folder and whether the
/// session works in that folder itself or in a worktree of it (and the worktree's branch).
struct SessionHeader: View {
    let row: SessionRow

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(conversationTitle(row)).font(.system(size: 14, weight: .semibold)).lineLimit(1)
            HStack(spacing: 8) {
                Label(row.workspace, systemImage: "folder.fill").lineLimit(1)
                if let branch = row.branch {
                    Badge(text: "Worktree", icon: "square.on.square", tint: .teal)
                    Label(branch, systemImage: "arrow.triangle.branch").font(.subheadline.monospaced()).lineLimit(1).truncationMode(.middle)
                } else {
                    Badge(text: "In the folder", icon: "folder", tint: .secondary)
                }
            }
            .font(.subheadline).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
        }
        .frame(maxWidth: 560, alignment: .leading)
        .help(row.branch == nil ? "Works in \(row.folder) itself" : "Works in a worktree of \(row.workspace): \(row.folder)")
        .accessibilityElement(children: .combine)
    }
}
