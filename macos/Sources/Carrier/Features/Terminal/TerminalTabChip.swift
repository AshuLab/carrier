import AppKit
import CarrierCore
import CarrierUI
import SwiftUI
import UniformTypeIdentifiers

struct TerminalTabChip: View {
    @Environment(\.pieceTheme) private var theme
    static let height: CGFloat = 32

    private var shape: Capsule { Capsule() }

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
        HStack(spacing: showsClose ? Tokens.Space.s2 : Tokens.Space.none) {
            Button(action: select) {
                HStack(spacing: Tokens.Space.s5) {
                    Glyph(.terminal, size: 10.5)
                        .foregroundStyle(selected ? theme.accent : .secondary)
                    Text(tab.title())
                        .scaledFont(12, weight: selected ? .medium : .regular)
                        .foregroundStyle(selected || hovered ? .primary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if tab.paneCount > 1 {
                        Text("\(tab.paneCount)")
                            .scaledFont(10, weight: .semibold).monospacedDigit()
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, Tokens.Space.s5)
                            .padding(.vertical, Tokens.Space.s1)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                            .accessibilityHidden(true)
                    }
                }
                .padding(.leading, Tokens.Space.s12)
                .padding(.trailing, showsClose ? Tokens.Space.s2 : Tokens.Space.s12)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tab.paneCount > 1 ? Copy.terminalTabWithPanes(title: tab.title(), count: tab.paneCount) : tab.title())
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityAction(named: Copy.terminalRenameTab()) {
                draftTitle = tab.customTitle ?? tab.title()
                renaming = true
            }

            if showsClose {
                Button(action: close) {
                    Glyph(.close, size: 8.5, bold: true)
                        .foregroundStyle(closeHovered ? .primary : .secondary)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Color.primary.opacity(closeHovered ? 0.14 : 0)))
                        .frame(width: 22, height: 22)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .onHover { closeHovered = $0 }
                .help(Copy.terminalCloseTabHelp())
                .accessibilityLabel(Copy.terminalCloseNamed(title: tab.title()))
            }
        }
        .accessibilityElement(children: .contain)
        .padding(.trailing, showsClose ? Tokens.Space.s4 : Tokens.Space.none)
        .frame(height: Self.height)
        .frame(maxWidth: 220)
        .clipShape(shape)
        .background(backgroundFill)
        .overlay(borderStroke)
        .contentShape(shape)
        .onMiddleClick(perform: close)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .animation(.easeOut(duration: 0.12), value: selected)
        .help(tooltipText)
        .contextMenu {
            Button {
                draftTitle = tab.customTitle ?? tab.title()
                renaming = true
            } label: {
                Label(Copy.terminalRenameTabEllipsis(), systemIcon: .pencil).labelStyle(.titleAndIcon)
            }
            if canMoveLeft || canMoveRight {
                Divider()
                if canMoveLeft {
                    Button(action: moveLeft) {
                        Label(Copy.terminalMoveTabLeft(), systemIcon: .arrowLeft).labelStyle(.titleAndIcon)
                    }
                }
                if canMoveRight {
                    Button(action: moveRight) {
                        Label(Copy.terminalMoveTabRight(), systemIcon: .arrowRight).labelStyle(.titleAndIcon)
                    }
                }
            }
            Divider()
            Button(action: close) {
                Label(Copy.terminalCloseTab(), systemIcon: .close).labelStyle(.titleAndIcon)
            }
            if canCloseOthers {
                Button(action: closeOthers) {
                    Label(Copy.terminalCloseOtherTabs(), systemIcon: .closeCircle).labelStyle(.titleAndIcon)
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
        .accessibilityAction(named: Copy.terminalCloseTab(), close)
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

    /// Flat at rest: the group is a quiet fill. Only the selected tab is glass; the hovered one and a drop target are filled.
    @ViewBuilder private var backgroundFill: some View {
        if isDropTarget {
            shape.fill(theme.accent.opacity(0.20))
        } else if selected {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            shape.fill(hovered ? Color.primary.opacity(0.07) : Color.clear)
        }
    }

    private var borderStroke: some View {
        shape.strokeBorder(isDropTarget ? theme.accent.opacity(0.60) : Color.clear, lineWidth: 1.5)
    }

    private var tooltipText: String {
        let folder = abbreviatedTerminalPath(tab.workingDirectory)
        if tab.paneCount > 1 {
            return Copy.terminalTabHelpWithPanes(title: tab.title(), count: tab.paneCount, folder: folder)
        }
        return Copy.terminalRowHelp(title: tab.title(), folder: folder)
    }
}
