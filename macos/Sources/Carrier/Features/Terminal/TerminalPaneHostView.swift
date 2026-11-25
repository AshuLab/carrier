import AppKit
import CarrierCore
import SwiftUI
import UniformTypeIdentifiers

struct TerminalPaneHostView: View {
    let store: CarrierTerminalStore
    let tab: TerminalTab
    let paneId: UUID
    let autoFocus: Bool
    let topControlsInset: CGFloat
    @Binding var draggedPaneId: UUID?
    let onSelectTab: ((UUID) -> Void)?

    @State private var dropZone: TerminalDropZone?
    @State private var topAreaHovered = false
    @State private var controlsHovered = false

    private static let hoverRevealHeight: CGFloat = 56

    private func closeCurrentPane() {
        if tab.panes.count > 1 {
            Task { _ = await store.closePane(id: paneId) }
        } else {
            Task { _ = await store.closeTab(id: tab.id) }
        }
    }

    var body: some View {
        let pane = tab.panes[paneId]
        let isSplit = tab.panes.count > 1
        let isZoomed = tab.zoomedPaneId == paneId
        let isInactiveSplitPane = isSplit && isZoomed == false && tab.activePaneId != paneId
        let shouldDimInactivePane = store.appearanceProfile.dimInactivePanes && isInactiveSplitPane
        let showControls = topAreaHovered || controlsHovered || draggedPaneId == paneId

        CarrierTerminalView(
            store: store,
            paneId: paneId,
            autoFocus: autoFocus && tab.activePaneId == paneId,
            isActivePane: tab.activePaneId == paneId,
            isSplit: isSplit,
            focusWhenActivated: store.appearanceProfile.focusFollowsMouse && isSplit
        ) { focused in
            if focused { store.selectPane(paneId) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .overlay {
            if shouldDimInactivePane {
                Rectangle()
                    .fill(Color(store.appearanceProfile.background).opacity(0.32))
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.14), value: shouldDimInactivePane)
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let location):
                let buttonsFree = NSEvent.pressedMouseButtons == 0
                topAreaHovered = buttonsFree
                    && location.y >= 0
                    && location.y <= Self.hoverRevealHeight + topControlsInset
                if store.appearanceProfile.focusFollowsMouse,
                   isSplit,
                   buttonsFree,
                   draggedPaneId == nil,
                   tab.activePaneId != paneId,
                   NSApp?.keyWindow != nil,
                   NSApp?.keyWindow?.attachedSheet == nil {
                    store.selectPane(paneId)
                }
            case .ended:
                topAreaHovered = false
            }
        }
        .overlay(alignment: .topTrailing) {
            if let pane {
                TerminalPaneHeaderView(
                    pane: pane,
                    isSplit: isSplit,
                    isZoomed: isZoomed,
                    onBeginDrag: {
                        draggedPaneId = paneId
                        scheduleTerminalDragCleanup(
                            isStillDragging: { draggedPaneId == paneId },
                            clear: { draggedPaneId = nil }
                        )
                        return NSItemProvider(object: paneId.uuidString as NSString)
                    },
                    splitRight: { _ = store.splitPane(paneId, edge: .trailing) },
                    splitDown: { _ = store.splitPane(paneId, edge: .bottom) },
                    toggleZoom: { store.toggleZoom(paneId: paneId) },
                    equalizeSplits: { store.equalizeSplits(inTab: tab.id) },
                    moveToNewTab: {
                        if let newTab = store.detachPaneToNewTab(paneId) {
                            onSelectTab?(newTab.id)
                        }
                    },
                    close: closeCurrentPane
                )
                .padding(.top, Tokens.Space.s8 + topControlsInset)
                .padding(.trailing, Tokens.Space.s8)
                .onHover { controlsHovered = $0 }
                .opacity(showControls ? 1 : 0)
                .allowsHitTesting(showControls)
                .accessibilityHidden(showControls == false)
                .animation(.easeOut(duration: 0.15), value: showControls)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: Copy.terminalSplitRight()) { _ = store.splitPane(paneId, edge: .trailing) }
        .accessibilityAction(named: Copy.terminalSplitDown()) { _ = store.splitPane(paneId, edge: .bottom) }
        .modifier(
            SplitPaneAccessibilityActions(
                isSplit: isSplit,
                isZoomed: isZoomed,
                onToggleZoom: { store.toggleZoom(paneId: paneId) },
                onEqualize: { store.equalizeSplits(inTab: tab.id) },
                onMoveToNewTab: {
                    if let newTab = store.detachPaneToNewTab(paneId) {
                        onSelectTab?(newTab.id)
                    }
                }
            )
        )
        .accessibilityAction(named: isSplit ? Copy.terminalClosePane() : Copy.terminalCloseTerminal(), closeCurrentPane)
        .overlay {
            if isSplit {
                GeometryReader { geometry in
                    ZStack {
                        if let dropZone {
                            TerminalDropOverlay(zone: dropZone)
                                .allowsHitTesting(false)
                        }
                        Color.clear
                            .contentShape(Rectangle())
                            .allowsHitTesting(draggedPaneId != nil && draggedPaneId != paneId)
                            .onDrop(
                                of: [UTType.plainText],
                                delegate: PaneDropDelegate(
                                    targetPaneId: paneId,
                                    size: geometry.size,
                                    store: store,
                                    draggedPaneId: $draggedPaneId,
                                    dropZone: $dropZone
                                )
                            )
                    }
                }
            }
        }
    }
}

private struct SplitPaneAccessibilityActions: ViewModifier {
    let isSplit: Bool
    let isZoomed: Bool
    let onToggleZoom: () -> Void
    let onEqualize: () -> Void
    let onMoveToNewTab: () -> Void

    func body(content: Content) -> some View {
        if isSplit {
            content
                .accessibilityAction(named: isZoomed ? Copy.terminalRestoreSplit() : Copy.terminalZoomPane(), onToggleZoom)
                .accessibilityAction(named: Copy.terminalEqualizeSplits(), onEqualize)
                .accessibilityAction(named: Copy.terminalMovePaneToNewTab(), onMoveToNewTab)
        } else {
            content
        }
    }
}
