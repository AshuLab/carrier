import AppKit
import CarrierCore
import SwiftUI
import UniformTypeIdentifiers

/// Floating hover-only pane controls aligned to the top-right corner of a terminal pane (shared across standalone Terminal views and the session drawer).
struct TerminalPaneHeaderView: View {
    let pane: TerminalPane
    let isSplit: Bool
    let isZoomed: Bool
    let onBeginDrag: (() -> NSItemProvider)?
    let splitRight: () -> Void
    let splitDown: () -> Void
    let toggleZoom: () -> Void
    let equalizeSplits: () -> Void
    let moveToNewTab: () -> Void
    let close: () -> Void

    @State private var dragHovered = false

    var body: some View {
        HStack(spacing: Tokens.Space.none) {
            if isSplit, let onBeginDrag {
                dragHandle(onBeginDrag: onBeginDrag)
                SettingsDivider(vertical: true)
                    .frame(height: 14)
            }
            ToolbarGlassIconButton(icon: .layoutColumns, name: Copy.terminalSplitRightName(), action: splitRight)
            ToolbarGlassIconButton(icon: .layoutRows, name: Copy.terminalSplitDownName(), action: splitDown)
            if isSplit {
                ToolbarGlassIconButton(
                    icon: isZoomed ? .arrowsMinimize : .arrowsMaximize,
                    name: isZoomed ? Copy.terminalRestoreSplitName() : Copy.terminalZoomPaneName(),
                    action: toggleZoom
                )
            }
            ToolbarGlassIconButton(icon: .close, name: isSplit ? Copy.terminalClosePaneName() : Copy.terminalCloseTerminalName(), action: close)
        }
        .glassEffect(.regular, in: .capsule)
        .contextMenu {
            Button(action: splitRight) {
                Label(Copy.terminalSplitRight(), systemIcon: .layoutColumns).labelStyle(.titleAndIcon)
            }
            Button(action: splitDown) {
                Label(Copy.terminalSplitDown(), systemIcon: .layoutRows).labelStyle(.titleAndIcon)
            }
            if isSplit {
                Button(action: toggleZoom) {
                    Label(
                        isZoomed ? Copy.terminalRestoreSplit() : Copy.terminalZoomPane(),
                        systemIcon: isZoomed ? .arrowsMinimize : .arrowsMaximize
                    ).labelStyle(.titleAndIcon)
                }
                Button(action: equalizeSplits) {
                    Label(Copy.terminalEqualizeSplits(), systemIcon: .columns3).labelStyle(.titleAndIcon)
                }
                Button(action: moveToNewTab) {
                    Label(Copy.terminalMovePaneToNewTab(), systemImage: "macwindow.badge.plus").labelStyle(.titleAndIcon)
                }
            }
            Divider()
            Button(role: .destructive, action: close) {
                Label(isSplit ? Copy.terminalClosePane() : Copy.terminalCloseTerminal(), systemIcon: .close).labelStyle(.titleAndIcon)
            }
        }
    }

    private func dragHandle(onBeginDrag: @escaping () -> NSItemProvider) -> some View {
        Glyph(.arrowsMove, size: 11)
            .foregroundStyle(.primary)
            .padding(.horizontal, Tokens.Space.s10)
            .frame(height: ToolbarPillButton.height)
            .background(Capsule().fill(Color.primary.opacity(dragHovered ? 0.1 : 0)))
            .contentShape(Capsule())
            .hoverCursor(.openHand) { dragHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: dragHovered)
            .help(Copy.terminalPaneDragHelp(title: pane.displayTitle(), folder: abbreviatedTerminalPath(pane.workingDirectory)))
            // not a button, so the icon inside is its own element: one element, with the label
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Copy.terminalPaneDragLabel(title: pane.displayTitle()))
            .onDrag(onBeginDrag)
    }
}
