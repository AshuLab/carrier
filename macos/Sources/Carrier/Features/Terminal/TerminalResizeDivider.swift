import AppKit
import CarrierCore
import SwiftUI
import UniformTypeIdentifiers

/// Shared 1 pt resize handle for split panes and the bottom terminal drawer with expanded hover/drag hit area and accessibility adjustment.
struct TerminalResizeDivider: View {
    @Environment(\.pieceTheme) private var theme
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
            .fill(hovered || isDragging ? theme.accent.opacity(0.65) : Color.primary.opacity(0.08))
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

extension View {
    func hoverCursor(_ cursor: NSCursor, onHoverChange: ((Bool) -> Void)? = nil) -> some View {
        modifier(HoverCursorModifier(cursor: cursor, onHoverChange: onHoverChange))
    }
}
