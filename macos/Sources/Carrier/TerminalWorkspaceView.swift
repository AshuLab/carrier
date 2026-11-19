import AppKit
import CarrierCore
import SwiftUI
import UniformTypeIdentifiers

/// Renders a live `TerminalTab`, either as a zoomed single pane or as a recursive split layout, with a unified header per pane.
struct TerminalSplitLayoutView: View {
    let store: CarrierTerminalStore
    let tab: TerminalTab
    var autoFocus: Bool = true
    var topControlsInset: CGFloat = 0
    var onSelectTab: ((UUID) -> Void)? = nil

    @State private var draggedPaneId: UUID?

    var body: some View {
        Group {
            if let zoomedId = tab.zoomedPaneId, tab.panes[zoomedId] != nil {
                TerminalPaneHostView(
                    store: store,
                    tab: tab,
                    paneId: zoomedId,
                    autoFocus: autoFocus,
                    topControlsInset: topControlsInset,
                    draggedPaneId: $draggedPaneId,
                    onSelectTab: onSelectTab
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                SplitTreeNodeView(
                    store: store,
                    tab: tab,
                    autoFocus: autoFocus,
                    topControlsInset: topControlsInset,
                    draggedPaneId: $draggedPaneId,
                    node: tab.root,
                    path: [],
                    onSelectTab: onSelectTab
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onDisappear { draggedPaneId = nil }
    }
}

/// Polls until mouse buttons release after a SwiftUI `onDrag`, clearing stale drag state if the drop is cancelled (e.g. Esc or outside drop).
@MainActor
func scheduleTerminalDragCleanup(
    isStillDragging: @escaping () -> Bool,
    clear: @escaping () -> Void
) {
    Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(50))
        while isStillDragging() && NSEvent.pressedMouseButtons != 0 {
            try? await Task.sleep(for: .milliseconds(50))
        }
        if isStillDragging() {
            // Yield briefly on the main actor so a completing `performDrop` runs before fallback cleanup.
            try? await Task.sleep(for: .milliseconds(50))
            if isStillDragging() { clear() }
        }
    }
}

/// Shared 1 pt resize handle for split panes and the bottom terminal drawer with expanded hover/drag hit area and accessibility adjustment.
private struct TerminalResizeDivider: View {
    let horizontal: Bool
    let isDragging: Bool
    let accessibilityLabel: String
    let accessibilityValue: String
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: () -> Void
    let onAdjust: (Bool) -> Void

    @State private var hovered = false

    var body: some View {
        Rectangle()
            .fill(hovered || isDragging ? Color.themeAccent.opacity(0.65) : Color.primary.opacity(0.08))
            .frame(width: horizontal ? 1 : nil, height: horizontal ? nil : 1)
            .frame(maxWidth: horizontal ? nil : .infinity, maxHeight: horizontal ? .infinity : nil)
            .contentShape(Rectangle().inset(by: -3))
            .hoverCursor(horizontal ? .resizeLeftRight : .resizeUpDown) { hovered = $0 }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let delta = horizontal ? value.translation.width : value.translation.height
                        onDragChanged(delta)
                    }
                    .onEnded { _ in
                        onDragEnded()
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(accessibilityValue)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: onAdjust(true)
                case .decrement: onAdjust(false)
                @unknown default: break
                }
            }
    }
}

/// Pushes `cursor` onto AppKit's cursor stack while hovered and always pops it cleanly on hover exit or disappear.
private struct HoverCursorModifier: ViewModifier {
    let cursor: NSCursor
    var onHoverChange: ((Bool) -> Void)? = nil
    @State private var pushed = false

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                onHoverChange?(inside)
                if inside && pushed == false {
                    cursor.push()
                    pushed = true
                } else if inside == false && pushed {
                    NSCursor.pop()
                    pushed = false
                }
            }
            .onDisappear {
                if pushed {
                    NSCursor.pop()
                    pushed = false
                }
            }
    }
}

private extension View {
    func hoverCursor(_ cursor: NSCursor, onHoverChange: ((Bool) -> Void)? = nil) -> some View {
        modifier(HoverCursorModifier(cursor: cursor, onHoverChange: onHoverChange))
    }
}

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
        HStack(spacing: 0) {
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
            .padding(.horizontal, 10)
            .frame(height: ToolbarPillButton.height)
            .background(Capsule().fill(Color.primary.opacity(dragHovered ? 0.1 : 0)))
            .contentShape(Capsule())
            .hoverCursor(.openHand) { dragHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: dragHovered)
            .help("\(pane.displayTitle) (\(abbreviatedTerminalPath(pane.workingDirectory))) — Drag to move or swap pane")
            .accessibilityLabel("Move pane \(pane.displayTitle)")
            .onDrag(onBeginDrag)
    }
}

private struct TerminalPaneHostView: View {
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
                .padding(.top, 8 + topControlsInset)
                .padding(.trailing, 8)
                .onHover { controlsHovered = $0 }
                .opacity(showControls ? 1 : 0)
                .allowsHitTesting(showControls)
                .accessibilityHidden(showControls == false)
                .animation(.easeOut(duration: 0.15), value: showControls)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Split Right") { _ = store.splitPane(paneId, edge: .trailing) }
        .accessibilityAction(named: "Split Down") { _ = store.splitPane(paneId, edge: .bottom) }
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
        .accessibilityAction(named: isSplit ? "Close Pane" : "Close Terminal", closeCurrentPane)
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
                .accessibilityAction(named: isZoomed ? "Restore Split View" : "Zoom Pane", onToggleZoom)
                .accessibilityAction(named: "Equalize Splits", onEqualize)
                .accessibilityAction(named: "Move Pane to New Tab", onMoveToNewTab)
        } else {
            content
        }
    }
}

private struct TerminalDropOverlay: View {
    let zone: TerminalDropZone

    var body: some View {
        GeometryReader { geometry in
            let frame = previewRect(in: geometry.size)
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.themeAccent.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.themeAccent.opacity(0.6), lineWidth: 1.5)
                )
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
                .animation(.easeOut(duration: 0.12), value: zone)
        }
    }

    private func previewRect(in size: CGSize) -> CGRect {
        switch zone {
        case .swap:
            CGRect(x: 4, y: 4, width: max(0, size.width - 8), height: max(0, size.height - 8))
        case .edge(.leading):
            CGRect(x: 4, y: 4, width: max(0, size.width * 0.5 - 6), height: max(0, size.height - 8))
        case .edge(.trailing):
            CGRect(x: size.width * 0.5 + 2, y: 4, width: max(0, size.width * 0.5 - 6), height: max(0, size.height - 8))
        case .edge(.top):
            CGRect(x: 4, y: 4, width: max(0, size.width - 8), height: max(0, size.height * 0.5 - 6))
        case .edge(.bottom):
            CGRect(x: 4, y: size.height * 0.5 + 2, width: max(0, size.width - 8), height: max(0, size.height * 0.5 - 6))
        }
    }
}

private struct PaneDropDelegate: DropDelegate {
    let targetPaneId: UUID
    let size: CGSize
    let store: CarrierTerminalStore
    @Binding var draggedPaneId: UUID?
    @Binding var dropZone: TerminalDropZone?

    func validateDrop(info: DropInfo) -> Bool {
        draggedPaneId != nil && draggedPaneId != targetPaneId
    }

    func dropEntered(info: DropInfo) {
        updateZone(info.location)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateZone(info.location)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        dropZone = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        let zone = terminalDropZone(
            x: Double(info.location.x),
            y: Double(info.location.y),
            width: Double(size.width),
            height: Double(size.height)
        )
        defer {
            dropZone = nil
            draggedPaneId = nil
        }
        guard let sourceId = draggedPaneId, sourceId != targetPaneId else { return false }
        switch zone {
        case .edge(let edge):
            return store.movePane(sourceId, toTarget: targetPaneId, edge: edge)
        case .swap:
            return store.swapPanes(sourceId, targetPaneId)
        }
    }

    private func updateZone(_ location: CGPoint) {
        dropZone = terminalDropZone(
            x: Double(location.x),
            y: Double(location.y),
            width: Double(size.width),
            height: Double(size.height)
        )
    }
}

private struct SplitTreeNodeView: View {
    let store: CarrierTerminalStore
    let tab: TerminalTab
    let autoFocus: Bool
    let topControlsInset: CGFloat
    @Binding var draggedPaneId: UUID?
    let node: SplitNode
    let path: [SplitBranch]
    let onSelectTab: ((UUID) -> Void)?

    var body: some View {
        switch node {
        case .leaf(let paneId):
            TerminalPaneHostView(
                store: store,
                tab: tab,
                paneId: paneId,
                autoFocus: autoFocus,
                topControlsInset: topControlsInset,
                draggedPaneId: $draggedPaneId,
                onSelectTab: onSelectTab
            )
        case .split(let axis, let ratio, let first, let second):
            SplitContainerView(
                store: store,
                tab: tab,
                autoFocus: autoFocus,
                topControlsInset: topControlsInset,
                draggedPaneId: $draggedPaneId,
                axis: axis,
                ratio: ratio,
                first: first,
                second: second,
                path: path,
                onSelectTab: onSelectTab
            )
        }
    }
}

private struct SplitContainerView: View {
    let store: CarrierTerminalStore
    let tab: TerminalTab
    let autoFocus: Bool
    let topControlsInset: CGFloat
    @Binding var draggedPaneId: UUID?
    let axis: SplitAxis
    let ratio: Double
    let first: SplitNode
    let second: SplitNode
    let path: [SplitBranch]
    let onSelectTab: ((UUID) -> Void)?

    @State private var dragBaseRatio: Double?

    private static let dividerThickness: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            let horizontal = axis == .horizontal
            let total = horizontal ? geometry.size.width : geometry.size.height
            let usable = max(0, total - Self.dividerThickness)
            let clampedRatio = SplitNode.clampRatio(ratio)
            let firstExtent = usable * clampedRatio
            let secondExtent = max(0, usable - firstExtent)

            if horizontal {
                HStack(spacing: 0) {
                    firstPane.frame(width: firstExtent, height: geometry.size.height)
                    divider(usable: usable, horizontal: true)
                    secondPane.frame(width: secondExtent, height: geometry.size.height)
                }
            } else {
                VStack(spacing: 0) {
                    firstPane.frame(width: geometry.size.width, height: firstExtent)
                    divider(usable: usable, horizontal: false)
                    secondPane.frame(width: geometry.size.width, height: secondExtent)
                }
            }
        }
    }

    private var firstPane: some View {
        SplitTreeNodeView(
            store: store,
            tab: tab,
            autoFocus: autoFocus,
            topControlsInset: topControlsInset,
            draggedPaneId: $draggedPaneId,
            node: first,
            path: path + [.first],
            onSelectTab: onSelectTab
        )
    }

    private var secondPane: some View {
        SplitTreeNodeView(
            store: store,
            tab: tab,
            autoFocus: autoFocus,
            topControlsInset: axis == .horizontal ? topControlsInset : 0,
            draggedPaneId: $draggedPaneId,
            node: second,
            path: path + [.second],
            onSelectTab: onSelectTab
        )
    }

    private func divider(usable: CGFloat, horizontal: Bool) -> some View {
        let clamped = SplitNode.clampRatio(ratio)
        return TerminalResizeDivider(
            horizontal: horizontal,
            isDragging: dragBaseRatio != nil,
            accessibilityLabel: horizontal ? "Vertical split divider" : "Horizontal split divider",
            accessibilityValue: "\(Int((clamped * 100).rounded())) percent",
            onDragChanged: { delta in
                guard usable > 0 else { return }
                let base = dragBaseRatio ?? clamped
                if dragBaseRatio == nil { dragBaseRatio = base }
                let next = SplitNode.clampRatio(base + Double(delta / usable))
                store.setSplitRatio(inTab: tab.id, at: path, ratio: next)
            },
            onDragEnded: {
                dragBaseRatio = nil
            },
            onAdjust: { increment in
                let next = SplitNode.clampRatio(clamped + (increment ? 0.05 : -0.05))
                store.setSplitRatio(inTab: tab.id, at: path, ratio: next)
            }
        )
    }
}

/// Full-size center detail view when an individual standalone terminal instance (and its group of tabs) is selected from Terminal.
struct TerminalDetailView: View {
    let store: CarrierTerminalStore
    let terminalId: UUID
    let newTerminal: () -> Void

    @State private var headerSafeInset: CGFloat = 0

    private var owner: TerminalOwner { .terminal(terminalId) }
    private var tabs: [TerminalTab] { store.tabs(for: owner) }
    private var activeTab: TerminalTab? { store.activeTab(for: owner) ?? tabs.first }

    var body: some View {
        Group {
            if let tab = activeTab {
                // Let the terminal surface extend behind the translucent top toolbar across the full detail height,
                // while offsetting top-edge floating pane controls below `headerSafeInset` so they never collide
                // with toolbar buttons and keeping the tab bar anchored cleanly below.
                GeometryReader { proxy in
                    let tabBarTotalHeight = TerminalTabBarView<EmptyView>.height + 1
                    VStack(spacing: 0) {
                        ScrollView {
                            TerminalSplitLayoutView(
                                store: store,
                                tab: tab,
                                autoFocus: true,
                                topControlsInset: headerSafeInset,
                                onSelectTab: { store.selectTab($0, for: owner) }
                            )
                            .id(tab.id)
                            .frame(
                                width: proxy.size.width,
                                height: max(0, proxy.size.height - tabBarTotalHeight)
                            )
                        }
                        .scrollDisabled(true)
                        .scrollIndicators(.hidden)
                        .scrollEdgeEffectStyle(.soft, for: .top)
                        .ignoresSafeArea(.container, edges: .top)

                        SettingsDivider()
                        TerminalTabBarView(
                            store: store,
                            tabs: tabs,
                            activeTabId: tab.id,
                            addTabLabel: "Add tab in \(abbreviatedTerminalPath(tab.workingDirectory))",
                            onSelectTab: { store.selectTab($0, for: owner) },
                            onAddTab: {
                                _ = store.openTab(for: owner, workingDirectory: tab.workingDirectory)
                            },
                            onCloseTab: { id in
                                Task { _ = await store.closeTab(id: id) }
                            },
                            onCloseOtherTabs: { keepingId in
                                Task { _ = await store.closeOtherTabs(except: keepingId, for: owner) }
                            }
                        )
                    }
                    .background {
                        if store.appearanceProfile.isSurfaceTranslucent == false {
                            Color(store.appearanceProfile.background)
                                .ignoresSafeArea(.container, edges: .top)
                        }
                    }
                }
                .ignoresSafeArea(.container, edges: .top)
                .toolbar { toolbar }
            } else {
                EmptyStateView(
                    state: .noTerminals,
                    action: ("New Terminal Session", newTerminal),
                    actionIcon: .plus,
                    actionStyle: .accentGlass
                )
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { headerSafeInset = $0 }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            AccentGlassPillButton(title: "New Terminal", icon: .plus, action: newTerminal)
                .padding(.trailing, 10)
                .help("New terminal")
        }
        .sharedBackgroundVisibility(.hidden)
    }
}

/// Bottom resizable drawer mounted under an active session conversation or epic view.
struct TerminalDrawerView: View {
    let store: CarrierTerminalStore
    let owner: TerminalOwner
    let defaultDirectory: String
    var openDefaultTabIfEmpty: Bool = true
    var dismissIcon: AppIcon = .chevronDown
    var dismissLabel: String = "Hide terminal"
    @Binding var height: CGFloat
    let maxHeight: CGFloat
    let dismissDrawer: () -> Void
    let autoHideOnEmpty: () -> Void

    @State private var dragStartHeight: CGFloat?

    private static let minHeight: CGFloat = 180

    private var tabs: [TerminalTab] { store.tabs(for: owner) }
    private var activeTab: TerminalTab? { store.activeTab(for: owner) ?? tabs.first }

    var body: some View {
        let clampedHeight = min(max(height, Self.minHeight), max(Self.minHeight, maxHeight))
        VStack(spacing: 0) {
            resizeHandle
            TerminalTabBarView(
                store: store,
                tabs: tabs,
                activeTabId: activeTab?.id,
                addTabLabel: "New terminal tab",
                onSelectTab: { store.selectTab($0, for: owner) },
                onAddTab: {
                    _ = store.openTab(for: owner, workingDirectory: activeTab?.workingDirectory ?? defaultDirectory)
                },
                onCloseTab: { id in Task { _ = await store.closeTab(id: id) } },
                onCloseOtherTabs: { keepingId in
                    Task { _ = await store.closeOtherTabs(except: keepingId, for: owner) }
                },
                trailingAccessory: {
                    IconButton(icon: dismissIcon, name: dismissLabel, action: dismissDrawer)
                }
            )
            SettingsDivider()
            if let activeTab {
                TerminalSplitLayoutView(
                    store: store,
                    tab: activeTab,
                    autoFocus: true,
                    onSelectTab: { store.selectTab($0, for: owner) }
                )
                .id(activeTab.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: clampedHeight)
        .background {
            let profile = store.appearanceProfile
            if profile.isSurfaceTranslucent {
                Rectangle()
                    .fill(.regularMaterial)
                    .overlay(Color(profile.chromeBackground))
            } else {
                Color(profile.background)
            }
        }
        .onAppear { ensureTabExists() }
        .onChange(of: owner) { _, _ in ensureTabExists() }
        .onChange(of: tabs.isEmpty) { _, isEmpty in
            if isEmpty { autoHideOnEmpty() }
        }
    }

    private func ensureTabExists() {
        if openDefaultTabIfEmpty, store.tabs(for: owner).isEmpty {
            _ = store.openTab(for: owner, workingDirectory: defaultDirectory)
        } else if openDefaultTabIfEmpty == false, store.tabs(for: owner).isEmpty {
            autoHideOnEmpty()
        }
    }

    private var resizeHandle: some View {
        let ceiling = max(Self.minHeight, maxHeight)
        return TerminalResizeDivider(
            horizontal: false,
            isDragging: dragStartHeight != nil,
            accessibilityLabel: "Terminal drawer resize handle",
            accessibilityValue: "\(Int(min(max(height, Self.minHeight), ceiling).rounded())) points",
            onDragChanged: { deltaY in
                let base = dragStartHeight ?? height
                if dragStartHeight == nil { dragStartHeight = base }
                let proposed = base - deltaY
                height = min(max(proposed, Self.minHeight), ceiling)
            },
            onDragEnded: {
                dragStartHeight = nil
            },
            onAdjust: { increment in
                height = min(max(height + (increment ? 24 : -24), Self.minHeight), ceiling)
            }
        )
    }
}
