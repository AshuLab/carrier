import CarrierCore
import SwiftUI

/// Where a session works, as a sheet: the folder itself or a new worktree, each with what it means. Choosing one closes the sheet.
struct WhereItWorksSheet: View {
    @Bindable var model: NewSessionModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                header
                VStack(spacing: 10) {
                    option(
                        "Current folder", "folder", chosen: model.worktree == false, worktree: false,
                        "Works in the folder itself, on the branch that is checked out (\(model.workspace?.branch ?? "detached HEAD")). What the agent changes lands in your working tree."
                    )
                    option(
                        "New worktree", "square.on.square", chosen: model.worktree, worktree: true,
                        "Works in a copy of the folder, on a new branch cut from the branch you pick. Your folder stays as it is."
                    )
                }
            }
            .padding(24)
            Divider()
            HStack {
                Spacer(minLength: 0)
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
        .frame(width: 520)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 16, weight: .medium)).foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.16)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Where it works").font(.title3.weight(.semibold))
                Text("How the session uses the folder.").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func option(_ title: String, _ icon: String, chosen: Bool, worktree: Bool, _ detail: String) -> some View {
        HoverRow(action: { Task { await model.useWorktree(worktree) }; dismiss() }, fill: chosen ? Color.accentColor.opacity(0.14) : nil) { _ in
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(chosen ? Color.accentColor : .secondary)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8).fill(chosen ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).fontWeight(.semibold)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if chosen {
                    ChosenMark()
                } else {
                    Image(systemName: "circle").foregroundStyle(.secondary.opacity(0.5)).font(.system(size: 16)).accessibilityLabel("Not chosen")
                }
            }
            .padding(12)
        }
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(chosen ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.2), lineWidth: 1))
    }
}
