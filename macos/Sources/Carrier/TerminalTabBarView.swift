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

struct TerminalTabChip: View {
    static let height: CGFloat = 26

    let tab: TerminalTab
    let index: Int
    let canMoveLeft: Bool
    let canMoveRight: Bool
    let selected: Bool
    let canCloseOthers: Bool
    @Binding var draggingTabId: UUID?
    @Binding var dropTargetTabId: UUID?
    let select: () -> Void
    let rename: (String?) -> Void
    let moveLeft: () -> Void
    let moveRight: () -> Void
    let close: () -> Void
    let closeOthers: () -> Void
    let reorder: (UUID, Int) -> Void

    @State private var hovered = false
    @State private var closeHovered = false
    @State private var renaming = false
    @State private var draftTitle = ""

    private var isDropTarget: Bool {
        dropTargetTabId == tab.id && draggingTabId != nil && draggingTabId != tab.id
    }

    var body: some View {
        let showsClose = hovered || selected
        HStack(spacing: showsClose ? 2 : 0) {
            Button(action: select) {
                HStack(spacing: 5) {
                    Glyph(.terminal)
                        .font(.scaled(10.5, weight: .medium))
                        .foregroundStyle(selected ? Color.themeAccent : .secondary)
                    Text(tab.title)
                        .font(.scaled(12, weight: selected ? .medium : .regular))
                        .foregroundStyle(selected || hovered ? .primary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if tab.paneCount > 1 {
                        Text("\(tab.paneCount)")
                            .font(.scaled(10, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                            .accessibilityHidden(true)
                    }
                }
                .padding(.leading, 10)
                .padding(.trailing, showsClose ? 2 : 10)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tab.paneCount > 1 ? "\(tab.title), \(tab.paneCount) panes" : tab.title)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityAction(named: "Rename Tab") {
                draftTitle = tab.customTitle ?? tab.title
                renaming = true
            }

            if showsClose {
                Button(action: close) {
                    Glyph(.close)
                        .font(.scaled(8.5, weight: .bold))
                        .foregroundStyle(closeHovered ? .primary : .secondary)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Color.primary.opacity(closeHovered ? 0.14 : 0)))
                        .frame(width: 22, height: 22)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .onHover { closeHovered = $0 }
                .help("Close tab")
                .accessibilityLabel("Close \(tab.title)")
            }
        }
        .accessibilityElement(children: .contain)
        .padding(.trailing, showsClose ? 4 : 0)
        .frame(height: Self.height)
        .frame(maxWidth: 220)
        .background(backgroundFill)
        .overlay(borderStroke)
        .clipShape(Capsule())
        .contentShape(Capsule())
        .onMiddleClick(perform: close)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .animation(.easeOut(duration: 0.12), value: selected)
        .help(tooltipText)
        .contextMenu {
            Button {
                draftTitle = tab.customTitle ?? tab.title
                renaming = true
            } label: {
                Label("Rename Tab…", menuIcon: .pencil).labelStyle(.titleAndIcon)
            }
            if canMoveLeft || canMoveRight {
                Divider()
                if canMoveLeft {
                    Button(action: moveLeft) {
                        Label("Move Tab Left", menuIcon: .arrowLeft).labelStyle(.titleAndIcon)
                    }
                }
                if canMoveRight {
                    Button(action: moveRight) {
                        Label("Move Tab Right", menuIcon: .arrowRight).labelStyle(.titleAndIcon)
                    }
                }
            }
            Divider()
            Button(action: close) {
                Label("Close Tab", menuIcon: .close).labelStyle(.titleAndIcon)
            }
            if canCloseOthers {
                Button(action: closeOthers) {
                    Label("Close Other Tabs", menuIcon: .closeCircle).labelStyle(.titleAndIcon)
                }
            }
        }
        .popover(isPresented: $renaming) {
            TabRenamePopover(
                title: $draftTitle,
                hasCustomTitle: tab.customTitle != nil,
                save: {
                    rename(draftTitle)
                    renaming = false
                },
                reset: {
                    rename(nil)
                    renaming = false
                },
                cancel: { renaming = false }
            )
        }
        .onDrag {
            draggingTabId = tab.id
            scheduleTerminalDragCleanup(
                isStillDragging: { draggingTabId == tab.id },
                clear: {
                    draggingTabId = nil
                    dropTargetTabId = nil
                }
            )
            return NSItemProvider(object: tab.id.uuidString as NSString)
        }
        .accessibilityAction(named: "Close Tab", close)
        .modifier(
            TabReorderAccessibilityActions(
                canMoveLeft: canMoveLeft,
                canMoveRight: canMoveRight,
                moveLeft: moveLeft,
                moveRight: moveRight
            )
        )
        .onDrop(
            of: [UTType.plainText],
            delegate: TerminalTabDropDelegate(
                targetTabId: tab.id,
                targetIndex: index,
                draggingTabId: $draggingTabId,
                dropTargetTabId: $dropTargetTabId,
                reorder: reorder
            )
        )
    }

    private var backgroundFill: some View {
        Capsule().fill(
            isDropTarget
                ? Color.themeAccent.opacity(0.20)
                : selected
                    ? Color.themeAccent.opacity(0.16)
                    : hovered ? Color.primary.opacity(0.08) : Color.primary.opacity(0.04)
        )
    }

    private var borderStroke: some View {
        Capsule().strokeBorder(
            isDropTarget
                ? Color.themeAccent.opacity(0.60)
                : selected
                    ? Color.themeAccent.opacity(0.32)
                    : hovered ? Color.primary.opacity(0.12) : Color.primary.opacity(0.06),
            lineWidth: isDropTarget ? 1.5 : 1
        )
    }

    private var tooltipText: String {
        let folder = abbreviatedTerminalPath(tab.workingDirectory)
        if tab.paneCount > 1 {
            return "\(tab.title) · \(tab.paneCount) panes\n\(folder)"
        }
        return "\(tab.title)\n\(folder)"
    }
}

private struct TerminalAddTabButton: View {
    let label: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Glyph(.plus)
                .font(.scaled(11, weight: .medium))
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

private struct TabRenamePopover: View {
    @Binding var title: String
    let hasCustomTitle: Bool
    let save: () -> Void
    let reset: () -> Void
    let cancel: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rename Tab")
                .font(.scaled(12, weight: .semibold))
            TextField("Tab name", text: $title)
                .settingsField(width: 248, focused: $focused)
                .onSubmit(save)
                .onKeyPress(.escape) {
                    cancel()
                    return .handled
                }
            HStack(spacing: 8) {
                if hasCustomTitle {
                    Button(action: reset) {
                        Label("Reset", icon: .rotate)
                    }
                    .buttonStyle(SecondaryCapsuleButtonStyle())
                    .controlSize(.small)
                }
                Spacer(minLength: 0)
                Button(action: cancel) {
                    Label("Cancel", icon: .close)
                }
                .buttonStyle(SecondaryCapsuleButtonStyle())
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)
                Button(action: save) {
                    Label("Save", icon: .check)
                }
                .buttonStyle(PrimaryCapsuleButtonStyle())
                .controlSize(.small)
            }
        }
        .padding(12)
        .onAppear { focused = true }
    }
}

private struct TabReorderAccessibilityActions: ViewModifier {
    let canMoveLeft: Bool
    let canMoveRight: Bool
    let moveLeft: () -> Void
    let moveRight: () -> Void

    func body(content: Content) -> some View {
        content
            .modifier(ConditionalAccessibilityAction(enabled: canMoveLeft, name: "Move Tab Left", action: moveLeft))
            .modifier(ConditionalAccessibilityAction(enabled: canMoveRight, name: "Move Tab Right", action: moveRight))
    }
}

private struct ConditionalAccessibilityAction: ViewModifier {
    let enabled: Bool
    let name: String
    let action: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.accessibilityAction(named: name, action)
        } else {
            content
        }
    }
}

private struct TerminalTabDropDelegate: DropDelegate {
    let targetTabId: UUID
    let targetIndex: Int
    @Binding var draggingTabId: UUID?
    @Binding var dropTargetTabId: UUID?
    let reorder: (UUID, Int) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        draggingTabId != nil
    }

    func dropEntered(info: DropInfo) {
        guard let sourceId = draggingTabId, sourceId != targetTabId else { return }
        dropTargetTabId = targetTabId
        reorder(sourceId, targetIndex)
    }

    func dropExited(info: DropInfo) {
        if dropTargetTabId == targetTabId {
            dropTargetTabId = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            draggingTabId = nil
            dropTargetTabId = nil
        }
        guard let sourceId = draggingTabId else { return false }
        if sourceId != targetTabId {
            reorder(sourceId, targetIndex)
        }
        return true
    }
}
