import AppKit
import CarrierCore
import SwiftUI

/// When a card last closed, shared by every row: the next one opens at once if it was a moment ago.
@MainActor private var lastCardClosedAt: Date?

extension View {
    /// Opens `card` beside the view when the pointer rests on it, keeps it while the pointer is on the view or on the card, and closes it
    /// a moment after it left both (`hoverCardStep`), and at once when the person clicks or scrolls in the window. A popover with an arrow,
    /// the system's own: the pointer can enter it and what is in it takes clicks. It takes none from the window under it: the first click on
    /// a row, or on a button of the row, is the row's whether its card is open or not (a popover the system closes for a click outside it
    /// swallows that click and the person has to click again).
    public func hoverCard<Card: View>(@ViewBuilder _ card: @escaping () -> Card) -> some View {
        modifier(HoverCard(card: card))
    }
}

private struct HoverCard<Card: View>: ViewModifier {
    let card: () -> Card
    @State private var shown = false
    @State private var onRow = false
    @State private var onCard = false
    @State private var pending: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { onRow = $0; moved() }
            .background(HoverCardPopover(shown: shown, card: card, onCard: { onCard = $0; moved() }, dismissed: dismiss))
    }

    private func moved() {
        pending?.cancel()
        switch hoverCardStep(onRow: onRow, onCard: onCard, shown: shown, closedAt: lastCardClosedAt, now: Date()) {
        case .open(let after):
            pending = Task {
                try? await Task.sleep(for: after)
                if Task.isCancelled == false { shown = true }
            }
        case .close(let after):
            pending = Task {
                try? await Task.sleep(for: after)
                guard Task.isCancelled == false else { return }
                shown = false
                lastCardClosedAt = Date()
            }
        case .keep: break
        }
    }

    /// The card went away on its own (a click or a scroll in the window, the app going to the background): nothing is waiting to open or close it.
    private func dismiss() {
        pending?.cancel()
        onCard = false
        guard shown else { return }
        shown = false
        lastCardClosedAt = Date()
    }
}

/// The view the popover points at, behind the row, and the popover itself: one that does not close for a click outside it (`applicationDefined`)
/// and so neither takes that click nor the window's focus; it ends with the first click or scroll of the window, and the event goes on.
private struct HoverCardPopover<Card: View>: NSViewRepresentable {
    let shown: Bool
    let card: () -> Card
    let onCard: (Bool) -> Void
    let dismissed: () -> Void

    func makeNSView(context: Context) -> AnchorView { AnchorView() }

    func updateNSView(_ view: AnchorView, context: Context) {
        context.coordinator.onCard = onCard
        context.coordinator.dismissed = dismissed
        if shown { context.coordinator.open(from: view, card: card) } else { context.coordinator.close() }
    }

    static func dismantleNSView(_ view: AnchorView, coordinator: Coordinator) { coordinator.close() }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Lets every click through to the row in front of it.
    final class AnchorView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    @MainActor final class Coordinator: NSObject, NSPopoverDelegate {
        var onCard: (Bool) -> Void = { _ in }
        var dismissed: () -> Void = {}
        private var popover: NSPopover?
        private var monitor: Any?
        private var resign: NSObjectProtocol?

        func open<Content: View>(from anchor: NSView, card: () -> Content) {
            guard popover == nil, anchor.window != nil, anchor.bounds.isEmpty == false else { return }
            let controller = NSHostingController(rootView: card().themed())
            controller.sizingOptions = [.preferredContentSize]
            let popover = NSPopover()
            popover.behavior = .applicationDefined
            popover.contentViewController = controller
            popover.delegate = self
            // the pointer on the card keeps it open: a tracking area of its own, which works while the window is not the key one
            controller.view.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxX)
            self.popover = popover
            // a click or a scroll anywhere in the window but the card ends it; the click is not taken, it goes on to what is under it
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]) { [weak self] event in
                MainActor.assumeIsolated {
                    if let self, let card = self.popover?.contentViewController?.view.window, event.window !== card { self.closeFromOutside() }
                }
                return event
            }
            resign = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.closeFromOutside() }
            }
        }

        /// Closes it for a reason of the view's own (its state says so, or the row went away).
        func close() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            if let resign { NotificationCenter.default.removeObserver(resign) }
            monitor = nil
            resign = nil
            let closing = popover
            popover = nil
            closing?.delegate = nil
            closing?.close()
        }

        private func closeFromOutside() {
            close()
            dismissed()
        }

        // MARK: the pointer on the card

        @objc func mouseEntered(with event: NSEvent) { onCard(true) }
        @objc func mouseExited(with event: NSEvent) { onCard(false) }

        // The window of the popover went away without being asked (the window closed): the card is over.
        func popoverDidClose(_ notification: Notification) {
            guard popover != nil else { return }
            closeFromOutside()
        }
    }
}
