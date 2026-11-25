import AppKit
import CarrierCore
import SwiftUI
import UniformTypeIdentifiers

struct TerminalDropOverlay: View {
    let zone: TerminalDropZone

    var body: some View {
        GeometryReader { geometry in
            let frame = previewRect(in: geometry.size)
            RoundedRectangle(cornerRadius: Tokens.Radius.small)
                .fill(Color.themeAccent.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.Radius.small)
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

struct PaneDropDelegate: DropDelegate {
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
