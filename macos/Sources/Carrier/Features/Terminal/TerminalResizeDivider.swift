import AppKit
import CarrierCore
import CarrierUI
import SwiftUI
import UniformTypeIdentifiers

/// Shared 1 pt resize handle for split panes and the bottom terminal drawer with expanded hover/drag hit area and accessibility adjustment.
struct TerminalResizeDivider: View {
    @Environment(\.pieceTheme) private var theme
    let horizontal: Bool
    /// The room the divider takes (the gap between two cards, or the edge of the drawer); what is drawn is only a line under the pointer.
    let thickness: CGFloat
    let isDragging: Bool
    let accessibilityLabel: String
    let accessibilityValue: String
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: () -> Void
    let onAdjust: (Bool) -> Void

    @State private var hovered = false

    var body: some View {
        Color.clear
            .frame(width: horizontal ? thickness : nil, height: horizontal ? nil : thickness)
            .frame(maxWidth: horizontal ? nil : .infinity, maxHeight: horizontal ? .infinity : nil)
            .overlay {
                Capsule()
                    .fill(theme.accent.opacity(hovered || isDragging ? 0.65 : 0))
                    .frame(width: horizontal ? 2 : nil, height: horizontal ? nil : 2)
                    .animation(.easeOut(duration: 0.12), value: hovered || isDragging)
            }
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

extension View {
    func hoverCursor(_ cursor: NSCursor, onHoverChange: ((Bool) -> Void)? = nil) -> some View {
        modifier(HoverCursorModifier(cursor: cursor, onHoverChange: onHoverChange))
    }
}
