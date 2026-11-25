import AppKit
import CarrierCore
import CarrierUI
import SwiftUI
import UniformTypeIdentifiers

/// Shared horizontal tab strip used by both standalone Terminal (`TerminalDetailView`) and the session/epic bottom drawer (`TerminalDrawerView`).
struct TerminalTabBarView<Trailing: View>: View {
    /// The glass group's height; the bar is this plus the margin above and below it.
    static var groupHeight: CGFloat { 40 }
    static var height: CGFloat { groupHeight + Tokens.Space.s8 * 2 }

    let store: CarrierTerminalStore
    let tabs: [TerminalTab]
    let activeTabId: UUID?
    var addTabLabel: String = Copy.terminalAddTab()
    let onSelectTab: (UUID) -> Void
    let onAddTab: () -> Void
    let onCloseTab: (UUID) -> Void
    var onCloseOtherTabs: ((UUID) -> Void)? = nil
    @ViewBuilder var trailingAccessory: () -> Trailing

    @State private var draggingTabId: UUID?
    @State private var dropTargetTabId: UUID?
    @State private var scroll = TabScrollState()

    /// How far the strip of tabs is from each end of its scroll view; the group is as wide as the tabs, up to the room it has.
    private struct TabScrollState: Equatable {
        var contentWidth: CGFloat?
        var moreBefore = false
        var moreAfter = false
    }

    private static var fadeWidth: CGFloat { 28 }

    var body: some View {
        HStack(spacing: Tokens.Space.s8) {
            tabGroup
            Spacer(minLength: Tokens.Space.none)
            TerminalBarButton(icon: .plus, name: addTabLabel, action: onAddTab)
            trailingAccessory()
        }
        .padding(.horizontal, Tokens.Space.s8)
        .frame(height: Self.height)
    }

    /// The tabs in a flat, quiet group that is as wide as they are; when they do not fit it scrolls and fades at the end that has more.
    private var tabGroup: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Tokens.Space.none) {
                    ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                        TerminalTabChip(
                            tab: tab,
                            index: index,
                            canMoveLeft: index > 0,
                            canMoveRight: index + 1 < tabs.count,
                            selected: activeTabId == tab.id,
                            canCloseOthers: tabs.count > 1 && onCloseOtherTabs != nil,
                            draggingTabId: $draggingTabId,
                            dropTargetTabId: $dropTargetTabId,
                            select: { onSelectTab(tab.id) },
                            rename: { title in store.renameTab(tab.id, customTitle: title) },
                            moveLeft: { _ = store.moveTabRelative(tab.id, offset: -1) },
                            moveRight: { _ = store.moveTabRelative(tab.id, offset: 1) },
                            close: { onCloseTab(tab.id) },
                            closeOthers: { onCloseOtherTabs?(tab.id) },
                            reorder: { sourceId, targetIndex in
                                store.moveTab(sourceId, toIndex: targetIndex)
                            }
                        )
                        .id(tab.id)
                        if index + 1 < tabs.count {
                            separator(hidden: tab.id == activeTabId || tabs[index + 1].id == activeTabId)
                        }
                    }
                }
            }
            .onScrollGeometryChange(for: TabScrollState.self) { geometry in
                TabScrollState(
                    contentWidth: geometry.contentSize.width,
                    moreBefore: geometry.contentOffset.x > 1,
                    moreAfter: geometry.contentOffset.x + geometry.containerSize.width < geometry.contentSize.width - 1
                )
            } action: { _, state in
                scroll = state
            }
            .mask { fadeMask }
            .onChange(of: activeTabId) { _, nextId in
                guard let nextId else { return }
                withAnimation(.easeOut(duration: 0.16)) {
                    proxy.scrollTo(nextId)
                }
            }
        }
        .frame(maxWidth: scroll.contentWidth ?? .infinity)
        .padding(Tokens.Space.s4)
        .frame(height: Self.groupHeight)
        .background(Capsule().fill(Color.primary.opacity(0.07)))
    }

    /// Opaque in the middle and clear at an end only while there is more to scroll to on that side.
    private var fadeMask: some View {
        HStack(spacing: Tokens.Space.none) {
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: scroll.moreBefore ? Self.fadeWidth : 0)
            Rectangle()
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: scroll.moreAfter ? Self.fadeWidth : 0)
        }
        .animation(.easeOut(duration: 0.15), value: scroll)
    }
}

extension TerminalTabBarView {
    /// A fine line between two flat tabs; it goes away next to the selected one, which has its own edge.
    private func separator(hidden: Bool) -> some View {
        Rectangle()
            .fill(Color.primary.opacity(hidden ? 0 : 0.16))
            .frame(width: 1, height: 14)
            .padding(.horizontal, Tokens.Space.s2)
            .animation(.easeOut(duration: 0.12), value: hidden)
            .accessibilityHidden(true)
    }
}

extension TerminalTabBarView where Trailing == EmptyView {
    init(
        store: CarrierTerminalStore,
        tabs: [TerminalTab],
        activeTabId: UUID?,
        addTabLabel: String = Copy.terminalAddTab(),
        onSelectTab: @escaping (UUID) -> Void,
        onAddTab: @escaping () -> Void,
        onCloseTab: @escaping (UUID) -> Void,
        onCloseOtherTabs: ((UUID) -> Void)? = nil
    ) {
        self.init(
            store: store,
            tabs: tabs,
            activeTabId: activeTabId,
            addTabLabel: addTabLabel,
            onSelectTab: onSelectTab,
            onAddTab: onAddTab,
            onCloseTab: onCloseTab,
            onCloseOtherTabs: onCloseOtherTabs,
            trailingAccessory: { EmptyView() }
        )
    }
}

/// A plain round button beside the tab group (add a tab, hide the drawer): bigger than a row's icon button, a faint fill under the pointer.
struct TerminalBarButton: View {
    let icon: AppIcon
    let name: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Glyph(icon, size: 16)
                .foregroundStyle(hovered ? .primary : .secondary)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.primary.opacity(hovered ? 0.1 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .help(name)
        .accessibilityLabel(name)
    }
}
