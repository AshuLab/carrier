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
                                selected: activeTabId == tab.id,
                                canCloseOthers: tabs.count > 1 && onCloseOtherTabs != nil,
                                draggingTabId: $draggingTabId,
                                dropTargetTabId: $dropTargetTabId,
                                select: { onSelectTab(tab.id) },
                                rename: { title in store.renameTab(tab.id, customTitle: title) },
                                close: { onCloseTab(tab.id) },
                                closeOthers: { onCloseOtherTabs?(tab.id) },
                                reorder: { sourceId, targetIndex in
                                    store.moveTab(sourceId, toIndex: targetIndex)
                                }
                            )
                            .id(tab.id)
                        }
                        TerminalAddTabButton(label: addTabLabel, action: onAddTab)
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
    let selected: Bool
    let canCloseOthers: Bool
    @Binding var draggingTabId: UUID?
    @Binding var dropTargetTabId: UUID?
    let select: () -> Void
    let rename: (String?) -> Void
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
        HStack(spacing: 6) {
            Button(action: select) {
                HStack(spacing: 5) {
                    Image(systemName: "terminal")
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
                            .accessibilityLabel("\(tab.paneCount) panes")
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])

            if hovered || selected {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.scaled(8.5, weight: .bold))
                        .foregroundStyle(closeHovered ? .primary : .secondary)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Color.primary.opacity(closeHovered ? 0.14 : 0)))
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .onHover { closeHovered = $0 }
                .help("Close tab")
                .accessibilityLabel("Close \(tab.title)")
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, (hovered || selected) ? 4 : 10)
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
                Label("Rename Tab…", systemImage: "pencil").labelStyle(.titleAndIcon)
            }
            Divider()
            Button(action: close) {
                Label("Close Tab", systemImage: "xmark").labelStyle(.titleAndIcon)
            }
            if canCloseOthers {
                Button(action: closeOthers) {
                    Label("Close Other Tabs", systemImage: "xmark.circle").labelStyle(.titleAndIcon)
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
        .accessibilityAction(named: "Rename Tab") {
            draftTitle = tab.customTitle ?? tab.title
            renaming = true
        }
        .accessibilityAction(named: "Close Tab", close)
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
            Image(systemName: "plus")
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
                .settingsField(width: 220, focused: $focused)
                .onSubmit(save)
                .onKeyPress(.escape) {
                    cancel()
                    return .handled
                }
            HStack(spacing: 8) {
                if hasCustomTitle {
                    Button(action: reset) {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(SecondaryCapsuleButtonStyle())
                    .controlSize(.small)
                }
                Spacer(minLength: 0)
                Button(action: cancel) {
                    Label("Cancel", systemImage: "xmark")
                }
                .buttonStyle(SecondaryCapsuleButtonStyle())
                .controlSize(.small)
                Button(action: save) {
                    Label("Save", systemImage: "checkmark")
                }
                .buttonStyle(PrimaryCapsuleButtonStyle())
                .controlSize(.small)
            }
        }
        .padding(12)
        .onAppear { focused = true }
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
