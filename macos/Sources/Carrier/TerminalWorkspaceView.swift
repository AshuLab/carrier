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
    var onCloseTab: (() -> Void)? = nil

    @State private var draggedPaneId: UUID?

    var body: some View {
        if let zoomedId = tab.zoomedPaneId, tab.panes[zoomedId] != nil {
            TerminalPaneHostView(
                store: store,
                tab: tab,
                paneId: zoomedId,
                autoFocus: autoFocus,
                topControlsInset: topControlsInset,
                draggedPaneId: $draggedPaneId,
                onSelectTab: onSelectTab,
                onCloseTab: onCloseTab
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
                onSelectTab: onSelectTab,
                onCloseTab: onCloseTab
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Floating hover-only pane controls aligned to the top-right corner of a terminal pane (shared across standalone Terminal views and the session drawer).
struct TerminalPaneHeaderView: View {
    let pane: TerminalPane
    let isSplit: Bool
    let isZoomed: Bool
    let canMoveToNewTab: Bool
    let onBeginDrag: (() -> NSItemProvider)?
    let splitRight: () -> Void
    let splitDown: () -> Void
    let toggleZoom: () -> Void
    let equalizeSplits: () -> Void
    let moveToNewTab: () -> Void
    let close: () -> Void

    @State private var dragHovered = false
    @State private var dragCursorPushed = false

    var body: some View {
        HStack(spacing: 0) {
            if isSplit, let onBeginDrag {
                dragHandle(onBeginDrag: onBeginDrag)
                SettingsDivider(vertical: true)
                    .frame(height: 14)
            }
            ToolbarGlassIconButton(icon: "rectangle.split.2x1", name: "Split right", action: splitRight)
            ToolbarGlassIconButton(icon: "rectangle.split.1x2", name: "Split down", action: splitDown)
            if isSplit {
                ToolbarGlassIconButton(
                    icon: isZoomed ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                    name: isZoomed ? "Restore split view" : "Zoom pane",
                    action: toggleZoom
                )
            }
            ToolbarGlassIconButton(icon: "xmark", name: isSplit ? "Close pane" : "Close terminal", action: close)
        }
        .glassEffect(.regular, in: .capsule)
        .contextMenu {
            Button(action: splitRight) {
                Label("Split Right", systemImage: "rectangle.split.2x1").labelStyle(.titleAndIcon)
            }
            Button(action: splitDown) {
                Label("Split Down", systemImage: "rectangle.split.1x2").labelStyle(.titleAndIcon)
            }
            if isSplit {
                Button(action: toggleZoom) {
                    Label(
                        isZoomed ? "Restore Split View" : "Zoom Pane",
                        systemImage: isZoomed ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
                    ).labelStyle(.titleAndIcon)
                }
                Button(action: equalizeSplits) {
                    Label("Equalize Splits", systemImage: "rectangle.split.3x1").labelStyle(.titleAndIcon)
                }
                if canMoveToNewTab {
                    Button(action: moveToNewTab) {
                        Label("Move to New Tab", systemImage: "macwindow.badge.plus").labelStyle(.titleAndIcon)
                    }
                }
            }
            Divider()
            Button(role: .destructive, action: close) {
                Label(isSplit ? "Close Pane" : "Close Terminal", systemImage: "xmark").labelStyle(.titleAndIcon)
            }
        }
    }

    private func dragHandle(onBeginDrag: @escaping () -> NSItemProvider) -> some View {
        Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
            .font(.scaled(11, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .frame(height: ToolbarPillButton.height)
            .background(Capsule().fill(Color.primary.opacity(dragHovered ? 0.1 : 0)))
            .contentShape(Capsule())
            .onHover { inside in
                dragHovered = inside
                if inside && dragCursorPushed == false {
                    NSCursor.openHand.push()
                    dragCursorPushed = true
                } else if inside == false && dragCursorPushed {
                    NSCursor.pop()
                    dragCursorPushed = false
                }
            }
            .onDisappear {
                if dragCursorPushed {
                    NSCursor.pop()
                    dragCursorPushed = false
                }
            }
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
    let onCloseTab: (() -> Void)?

    @State private var dropZone: TerminalDropZone?
    @State private var topAreaHovered = false
    @State private var controlsHovered = false

    private static let hoverRevealHeight: CGFloat = 56

    var body: some View {
        let pane = tab.panes[paneId]
        let isSplit = tab.panes.count > 1
        let isZoomed = tab.zoomedPaneId == paneId
        let showControls = topAreaHovered || controlsHovered || draggedPaneId == paneId

        CarrierTerminalView(
            store: store,
            paneId: paneId,
            autoFocus: autoFocus && tab.activePaneId == paneId
        ) { focused in
            if focused { store.selectPane(paneId) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let location):
                topAreaHovered = NSEvent.pressedMouseButtons == 0
                    && location.y >= 0
                    && location.y <= Self.hoverRevealHeight + topControlsInset
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
                    canMoveToNewTab: tab.owner != .quick || store.tabs(for: .quick).isEmpty == false,
                    onBeginDrag: {
                        draggedPaneId = paneId
                        DispatchQueue.main.async {
                            if NSEvent.pressedMouseButtons == 0 && draggedPaneId == paneId {
                                draggedPaneId = nil
                            }
                        }
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
                    close: {
                        if isSplit {
                            Task { _ = await store.closePane(id: paneId) }
                        } else if let onCloseTab {
                            onCloseTab()
                        } else {
                            Task { _ = await store.closeTab(id: tab.id) }
                        }
                    }
                )
                .padding(.top, 8 + topControlsInset)
                .padding(.trailing, 8)
                .onHover { controlsHovered = $0 }
                .opacity(showControls ? 1 : 0)
                .allowsHitTesting(showControls)
                .animation(.easeOut(duration: 0.15), value: showControls)
            }
        }
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
    let onCloseTab: (() -> Void)?

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
                onSelectTab: onSelectTab,
                onCloseTab: onCloseTab
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
                onSelectTab: onSelectTab,
                onCloseTab: onCloseTab
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
    let onCloseTab: (() -> Void)?

    @State private var dragBaseRatio: Double?
    @State private var dividerHovered = false
    @State private var cursorPushed = false

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
            onSelectTab: onSelectTab,
            onCloseTab: onCloseTab
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
            onSelectTab: onSelectTab,
            onCloseTab: onCloseTab
        )
    }

    private func divider(usable: CGFloat, horizontal: Bool) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.primary.opacity(dividerHovered || dragBaseRatio != nil ? 0.24 : 0.08))
                .frame(width: horizontal ? Self.dividerThickness : nil, height: horizontal ? nil : Self.dividerThickness)
        }
        .frame(width: horizontal ? 7 : nil, height: horizontal ? nil : 7)
        .frame(width: horizontal ? Self.dividerThickness : nil, height: horizontal ? nil : Self.dividerThickness)
        .contentShape(Rectangle().inset(by: -3))
        .onHover { inside in
            dividerHovered = inside
            if inside && cursorPushed == false {
                (horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
                cursorPushed = true
            } else if inside == false && cursorPushed {
                NSCursor.pop()
                cursorPushed = false
            }
        }
        .onDisappear {
            if cursorPushed {
                NSCursor.pop()
                cursorPushed = false
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    guard usable > 0 else { return }
                    let base = dragBaseRatio ?? SplitNode.clampRatio(ratio)
                    if dragBaseRatio == nil { dragBaseRatio = base }
                    let delta = horizontal ? value.translation.width : value.translation.height
                    let next = SplitNode.clampRatio(base + Double(delta / usable))
                    store.setSplitRatio(inTab: tab.id, at: path, ratio: next)
                }
                .onEnded { _ in
                    dragBaseRatio = nil
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
                }
                .ignoresSafeArea(.container, edges: .top)
                .toolbar { toolbar }
            } else {
                EmptyStateView(
                    state: .noTerminals,
                    action: ("New Terminal Session", newTerminal),
                    actionIcon: "plus",
                    actionStyle: .accentGlass
                )
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { headerSafeInset = $0 }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            AccentGlassPillButton(title: "New Terminal", icon: "plus", action: newTerminal)
                .padding(.trailing, 10)
                .help("New terminal")
        }
        .sharedBackgroundVisibility(.hidden)
    }
}

/// Bottom resizable drawer mounted under an active session conversation, initialized in that session's working folder.
struct SessionTerminalDrawerView: View {
    let store: CarrierTerminalStore
    let sessionId: String
    let defaultDirectory: String
    @Binding var height: CGFloat
    let maxHeight: CGFloat
    let hideDrawer: () -> Void

    @State private var dragStartHeight: CGFloat?
    @State private var resizeHovered = false
    @State private var cursorPushed = false

    private static let minHeight: CGFloat = 180

    private var owner: TerminalOwner { .session(sessionId) }
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
                onAddTab: { _ = store.openTab(for: owner, workingDirectory: defaultDirectory) },
                onCloseTab: { id in Task { _ = await store.closeTab(id: id) } },
                onCloseOtherTabs: { keepingId in
                    Task { _ = await store.closeOtherTabs(except: keepingId, for: owner) }
                },
                trailingAccessory: {
                    IconButton(icon: "chevron.down", name: "Hide terminal", action: hideDrawer)
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
            } else {
                EmptyView()
            }
        }
        .frame(height: clampedHeight)
        .background(Color.themeWindow)
        .onAppear { ensureTabExists() }
        .onChange(of: sessionId) { _, _ in ensureTabExists() }
        .onChange(of: tabs.isEmpty) { _, isEmpty in
            if isEmpty { hideDrawer() }
        }
    }

    private func ensureTabExists() {
        if store.tabs(for: owner).isEmpty {
            _ = store.openTab(for: owner, workingDirectory: defaultDirectory)
        }
    }

    private var resizeHandle: some View {
        ZStack {
            Rectangle()
                .fill(Color.primary.opacity(resizeHovered || dragStartHeight != nil ? 0.24 : 0.08))
                .frame(height: 1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 7)
        .frame(height: 1)
        .contentShape(Rectangle().inset(by: -3))
        .onHover { inside in
            resizeHovered = inside
            if inside && cursorPushed == false {
                NSCursor.resizeUpDown.push()
                cursorPushed = true
            } else if inside == false && cursorPushed {
                NSCursor.pop()
                cursorPushed = false
            }
        }
        .onDisappear {
            if cursorPushed {
                NSCursor.pop()
                cursorPushed = false
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    let base = dragStartHeight ?? height
                    if dragStartHeight == nil { dragStartHeight = base }
                    let proposed = base - value.translation.height
                    height = min(max(proposed, Self.minHeight), max(Self.minHeight, maxHeight))
                }
                .onEnded { _ in
                    dragStartHeight = nil
                }
        )
    }
}
