import CarrierCore
import SwiftUI

/// Where a session works, as a sheet: the folder itself or a new worktree, each with what it means. Choosing one closes the sheet.
struct WhereItWorksSheet: View {
    @Environment(\.pieceTheme) private var theme
    @Bindable var model: NewSessionModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Tokens.Space.none) {
            VStack(alignment: .leading, spacing: Tokens.Space.s20) {
                header
                VStack(spacing: Tokens.Space.s10) {
                    option(
                        Copy.newSessionCurrentFolder(), .folder, chosen: model.worktree == false, worktree: false,
                        Copy.newSessionWhereFolderDetail(branch: model.workspace?.branch ?? Copy.newSessionDetachedHead())
                    )
                    option(
                        Copy.newSessionNewWorktree(), .copy, chosen: model.worktree, worktree: true,
                        Copy.newSessionWhereWorktreeDetail()
                    )
                }
            }
            .padding(Tokens.Space.s24)
            Divider()
            HStack {
                Spacer(minLength: 0)
                Button(Copy.projectsCancel()) { dismiss() }.buttonStyle(SecondaryCapsuleButtonStyle()).keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, Tokens.Space.s20).padding(.vertical, Tokens.Space.s12)
        }
        .frame(width: 520)
    }

    private var header: some View {
        HStack(spacing: Tokens.Space.s12) {
            Glyph(.gitBranch, size: 16).foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: Tokens.Radius.control).fill(.tint.opacity(0.16)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                Text(Copy.newSessionWhereItWorks()).font(.title3.weight(.semibold))
                Text(Copy.newSessionWhereSubtitle()).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func option(_ title: String, _ icon: AppIcon, chosen: Bool, worktree: Bool, _ detail: String) -> some View {
        HoverRow(action: { Task { await model.useWorktree(worktree) }; dismiss() }, fill: chosen ? theme.accent.opacity(0.14) : nil) { _ in
            HStack(alignment: .top, spacing: Tokens.Space.s12) {
                Glyph(icon, size: 14).foregroundStyle(chosen ? theme.accent : .secondary)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: Tokens.Radius.control).fill(chosen ? theme.accent.opacity(0.18) : Color.secondary.opacity(0.12)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                    Text(title).fontWeight(.semibold)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if chosen {
                    ChosenMark()
                } else {
                    Glyph(.circle, size: 16, label: Copy.newSessionNotChosen()).foregroundStyle(.secondary.opacity(0.5))
                }
            }
            .padding(Tokens.Space.s12)
        }
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.control).strokeBorder(chosen ? theme.accent.opacity(0.6) : Color.secondary.opacity(0.2), lineWidth: 1))
    }
}
