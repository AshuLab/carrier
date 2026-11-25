import AppKit
import CarrierCore
import SwiftUI
import UniformTypeIdentifiers

struct TabReorderAccessibilityActions: ViewModifier {
    let canMoveLeft: Bool
    let canMoveRight: Bool
    let moveLeft: () -> Void
    let moveRight: () -> Void

    func body(content: Content) -> some View {
        content
            .modifier(ConditionalAccessibilityAction(enabled: canMoveLeft, name: Copy.terminalMoveTabLeft(), action: moveLeft))
            .modifier(ConditionalAccessibilityAction(enabled: canMoveRight, name: Copy.terminalMoveTabRight(), action: moveRight))
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

struct TerminalTabDropDelegate: DropDelegate {
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
