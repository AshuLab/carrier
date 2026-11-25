import AppKit
import CarrierCore
import SwiftUI
import UniformTypeIdentifiers

/// Renders a live `TerminalTab`, either as a zoomed single pane or as a recursive split layout, with a unified header per pane.
struct TerminalSplitLayoutView: View {
    let store: CarrierTerminalStore
    let tab: TerminalTab
    var autoFocus: Bool = true
    var topControlsInset: CGFloat = 0
    var onSelectTab: ((UUID) -> Void)? = nil

    @State private var draggedPaneId: UUID?

    var body: some View {
        Group {
            if let zoomedId = tab.zoomedPaneId, tab.panes[zoomedId] != nil {
                TerminalPaneHostView(
                    store: store,
                    tab: tab,
                    paneId: zoomedId,
                    autoFocus: autoFocus,
                    topControlsInset: topControlsInset,
                    draggedPaneId: $draggedPaneId,
                    onSelectTab: onSelectTab
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                SplitTreeNodeView(
                    store: store,
                    tab: tab,
                    autoFocus: autoFocus,
                    topControlsInset: topControlsInset,
                    draggedPaneId: $draggedPaneId,
                    node: tab.root,
                    path: [],
                    onSelectTab: onSelectTab
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onDisappear { draggedPaneId = nil }
    }
}

/// Polls until mouse buttons release after a SwiftUI `onDrag`, clearing stale drag state if the drop is cancelled (e.g. Esc or outside drop).
@MainActor
func scheduleTerminalDragCleanup(
    isStillDragging: @escaping () -> Bool,
    clear: @escaping () -> Void
) {
    Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(50))
        while isStillDragging() && NSEvent.pressedMouseButtons != 0 {
            try? await Task.sleep(for: .milliseconds(50))
        }
        if isStillDragging() {
            // Yield briefly on the main actor so a completing `performDrop` runs before fallback cleanup.
            try? await Task.sleep(for: .milliseconds(50))
            if isStillDragging() { clear() }
        }
    }
}

private struct SplitTreeNodeView: View {
    let store: CarrierTerminalStore
    let tab: TerminalTab
    let autoFocus: Bool
    let topControlsInset: CGFloat
    @Binding var draggedPaneId: UUID?
    let node: SplitNode
    let path: [SplitBranch]
    let onSelectTab: ((UUID) -> Void)?

    var body: some View {
        switch node {
        case .leaf(let paneId):
            TerminalPaneHostView(
                store: store,
                tab: tab,
                paneId: paneId,
                autoFocus: autoFocus,
                topControlsInset: topControlsInset,
                draggedPaneId: $draggedPaneId,
                onSelectTab: onSelectTab
            )
        case .split(let axis, let ratio, let first, let second):
            SplitContainerView(
                store: store,
                tab: tab,
                autoFocus: autoFocus,
                topControlsInset: topControlsInset,
                draggedPaneId: $draggedPaneId,
                axis: axis,
                ratio: ratio,
                first: first,
                second: second,
                path: path,
                onSelectTab: onSelectTab
            )
        }
    }
}

private struct SplitContainerView: View {
    let store: CarrierTerminalStore
    let tab: TerminalTab
    let autoFocus: Bool
    let topControlsInset: CGFloat
    @Binding var draggedPaneId: UUID?
    let axis: SplitAxis
    let ratio: Double
    let first: SplitNode
    let second: SplitNode
    let path: [SplitBranch]
    let onSelectTab: ((UUID) -> Void)?

    @State private var dragBaseRatio: Double?

    private static let dividerThickness: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            let horizontal = axis == .horizontal
            let total = horizontal ? geometry.size.width : geometry.size.height
            let usable = max(0, total - Self.dividerThickness)
            let clampedRatio = SplitNode.clampRatio(ratio)
            let firstExtent = usable * clampedRatio
            let secondExtent = max(0, usable - firstExtent)

            if horizontal {
                HStack(spacing: Tokens.Space.none) {
                    firstPane.frame(width: firstExtent, height: geometry.size.height)
                    divider(usable: usable, horizontal: true)
                    secondPane.frame(width: secondExtent, height: geometry.size.height)
                }
            } else {
                VStack(spacing: Tokens.Space.none) {
                    firstPane.frame(width: geometry.size.width, height: firstExtent)
                    divider(usable: usable, horizontal: false)
                    secondPane.frame(width: geometry.size.width, height: secondExtent)
                }
            }
        }
    }

    private var firstPane: some View {
        SplitTreeNodeView(
            store: store,
            tab: tab,
            autoFocus: autoFocus,
            topControlsInset: topControlsInset,
            draggedPaneId: $draggedPaneId,
            node: first,
            path: path + [.first],
            onSelectTab: onSelectTab
        )
    }

    private var secondPane: some View {
        SplitTreeNodeView(
            store: store,
            tab: tab,
            autoFocus: autoFocus,
            topControlsInset: axis == .horizontal ? topControlsInset : 0,
            draggedPaneId: $draggedPaneId,
            node: second,
            path: path + [.second],
            onSelectTab: onSelectTab
        )
    }

    private func divider(usable: CGFloat, horizontal: Bool) -> some View {
        let clamped = SplitNode.clampRatio(ratio)
        return TerminalResizeDivider(
            horizontal: horizontal,
            isDragging: dragBaseRatio != nil,
            accessibilityLabel: horizontal ? Copy.terminalDividerVertical() : Copy.terminalDividerHorizontal(),
            accessibilityValue: Copy.terminalPercentValue(percent: Int((clamped * 100).rounded())),
            onDragChanged: { delta in
                guard usable > 0 else { return }
                let base = dragBaseRatio ?? clamped
                if dragBaseRatio == nil { dragBaseRatio = base }
                let next = SplitNode.clampRatio(base + Double(delta / usable))
                store.setSplitRatio(inTab: tab.id, at: path, ratio: next)
            },
            onDragEnded: {
                dragBaseRatio = nil
            },
            onAdjust: { increment in
                let next = SplitNode.clampRatio(clamped + (increment ? 0.05 : -0.05))
                store.setSplitRatio(inTab: tab.id, at: path, ratio: next)
            }
        )
    }
}
