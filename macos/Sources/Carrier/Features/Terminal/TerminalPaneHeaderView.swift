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
            ToolbarGlassIconButton(icon: .layoutColumns, name: "Split right", action: splitRight)
            ToolbarGlassIconButton(icon: .layoutRows, name: "Split down", action: splitDown)
            if isSplit {
                ToolbarGlassIconButton(
                    icon: isZoomed ? .arrowsMinimize : .arrowsMaximize,
                    name: isZoomed ? "Restore split view" : "Zoom pane",
                    action: toggleZoom
                )
            }
            ToolbarGlassIconButton(icon: .close, name: isSplit ? "Close pane" : "Close terminal", action: close)
        }
        .glassEffect(.regular, in: .capsule)
        .contextMenu {
            Button(action: splitRight) {
                Label("Split Right", systemIcon: .layoutColumns).labelStyle(.titleAndIcon)
            }
            Button(action: splitDown) {
                Label("Split Down", systemIcon: .layoutRows).labelStyle(.titleAndIcon)
            }
            if isSplit {
                Button(action: toggleZoom) {
                    Label(
                        isZoomed ? "Restore Split View" : "Zoom Pane",
                        systemIcon: isZoomed ? .arrowsMinimize : .arrowsMaximize
                    ).labelStyle(.titleAndIcon)
                }
                Button(action: equalizeSplits) {
                    Label("Equalize Splits", systemIcon: .columns3).labelStyle(.titleAndIcon)
                }
                Button(action: moveToNewTab) {
                    Label("Move Pane to New Tab", systemImage: "macwindow.badge.plus").labelStyle(.titleAndIcon)
                }
            }
            Divider()
            Button(role: .destructive, action: close) {
                Label(isSplit ? "Close Pane" : "Close Terminal", systemIcon: .close).labelStyle(.titleAndIcon)
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
            .help("\(pane.displayTitle) (\(abbreviatedTerminalPath(pane.workingDirectory))) — Drag to move or swap pane")
            // not a button, so the icon inside is its own element: one element, with the label
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Move pane \(pane.displayTitle)")
            .onDrag(onBeginDrag)
    }
}
