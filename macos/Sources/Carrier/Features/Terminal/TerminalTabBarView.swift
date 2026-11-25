import AppKit
import CarrierCore
import SwiftUI
import UniformTypeIdentifiers

/// Shared horizontal tab strip used by both standalone Terminal (`TerminalDetailView`) and the session/epic bottom drawer (`TerminalDrawerView`).
struct TerminalTabBarView<Trailing: View>: View {
    static var height: CGFloat { 36 }

    let store: CarrierTerminalStore
    let tabs: [TerminalTab]
    let activeTabId: UUID?
    var addTabLabel: String = "Add tab"
    let onSelectTab: (UUID) -> Void
    let onAddTab: () -> Void
    let onCloseTab: (UUID) -> Void
    var onCloseOtherTabs: ((UUID) -> Void)? = nil
    @ViewBuilder var trailingAccessory: () -> Trailing

    @State private var draggingTabId: UUID?
    @State private var dropTargetTabId: UUID?

    var body: some View {
        HStack(spacing: 6) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
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
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: activeTabId) { _, nextId in
                    guard let nextId else { return }
                    withAnimation(.easeOut(duration: 0.16)) {
                        proxy.scrollTo(nextId)
                    }
                }
            }
            TerminalAddTabButton(label: addTabLabel, action: onAddTab)
            trailingAccessory()
        }
        .padding(.horizontal, 12)
        .frame(height: Self.height)
    }
}

extension TerminalTabBarView where Trailing == EmptyView {
    init(
        store: CarrierTerminalStore,
        tabs: [TerminalTab],
        activeTabId: UUID?,
        addTabLabel: String = "Add tab",
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

private struct TerminalAddTabButton: View {
    let label: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Glyph(.plus, size: 11)
                .foregroundStyle(hovered ? .primary : .secondary)
                .frame(width: TerminalTabChip.height, height: TerminalTabChip.height)
                .background(Circle().fill(Color.primary.opacity(hovered ? 0.1 : 0.04)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .help(label)
        .accessibilityLabel(label)
    }
}
