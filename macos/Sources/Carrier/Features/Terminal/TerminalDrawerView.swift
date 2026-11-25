import AppKit
import CarrierCore
import SwiftUI
import UniformTypeIdentifiers

/// Bottom resizable drawer mounted under an active session conversation or epic view.
struct TerminalDrawerView: View {
    let store: CarrierTerminalStore
    let owner: TerminalOwner
    let defaultDirectory: String
    var openDefaultTabIfEmpty: Bool = true
    var dismissIcon: AppIcon = .chevronDown
    var dismissLabel: String = Copy.terminalHide()
    @Binding var height: CGFloat
    let maxHeight: CGFloat
    let dismissDrawer: () -> Void
    let autoHideOnEmpty: () -> Void

    @State private var dragStartHeight: CGFloat?
    /// The height while the edge is dragged: drawn from here, and written to `height` (the defaults) once, when the drag ends.
    @State private var dragHeight: CGFloat?

    private static let minHeight: CGFloat = 180

    private var tabs: [TerminalTab] { store.tabs(for: owner) }
    private var activeTab: TerminalTab? { store.activeTab(for: owner) ?? tabs.first }

    var body: some View {
        let clampedHeight = min(max(dragHeight ?? height, Self.minHeight), max(Self.minHeight, maxHeight))
        VStack(spacing: Tokens.Space.none) {
            resizeHandle
            TerminalTabBarView(
                store: store,
                tabs: tabs,
                activeTabId: activeTab?.id,
                addTabLabel: Copy.terminalNewTabInDrawer(),
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
        .onDisappear {
            // the drawer goes away in the middle of a drag: what was drawn is kept, as it would have been on release
            if let dragHeight { height = dragHeight }
            dragHeight = nil
            dragStartHeight = nil
        }
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
            accessibilityLabel: Copy.terminalDrawerHandle(),
            accessibilityValue: Copy.terminalPointsValue(count: Int(min(max(dragHeight ?? height, Self.minHeight), ceiling).rounded())),
            onDragChanged: { deltaY in
                let base = dragStartHeight ?? height
                if dragStartHeight == nil { dragStartHeight = base }
                dragHeight = min(max(base - deltaY, Self.minHeight), ceiling)
            },
            onDragEnded: {
                // the defaults are written once per drag, not at every tick of it
                if let dragHeight { height = dragHeight }
                dragHeight = nil
                dragStartHeight = nil
            },
            onAdjust: { increment in
                // from what is drawn, and the drag state is over: a drag that never reported its end must not hold the drawn height
                let base = dragHeight ?? height
                dragHeight = nil
                dragStartHeight = nil
                height = min(max(base + (increment ? 24 : -24), Self.minHeight), ceiling)
            }
        )
    }
}
