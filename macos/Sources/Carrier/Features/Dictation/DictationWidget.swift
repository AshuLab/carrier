import AppKit
import CarrierCore
import CarrierUI
import SwiftUI

/// The widget of a global dictation: a panel that never takes the focus from the app the person is in (it is not main and does not activate Carrier,
/// and it is key only for the text that was left on it with its buttons). It takes the pointer, to be dragged: where it is let go is kept (`AppPreferences.dictationWidgetSpot`)
/// and it opens there next time. Its style, theme and place are the person's (`AppPreferences.dictationWidgetStyle`, `dictationWidgetPreview`, `dictationWidgetTheme`,
/// `dictationWidgetPosition` and the spot, read each time it opens), its look for a state is `dictationWidgetLook`, and it follows `GlobalDictation.shown`,
/// resizing as the look changes. It is glass in the theme, and while it listens it draws the message box's line (`DictationIndicator`) around the box,
/// which is why the panel is `glow` points larger than the box on each side. It holds the text, the time, the shortcut and Esc.
@MainActor final class DictationWidget {
    /// How long it takes the check, the warning or the x to fade (how long they stay is `DictationWidgetLook.linger`).
    static let fade = 0.3
    /// The room the listening line and the shadow have around the box, inside the panel.
    static let glow: CGFloat = 14
    /// How far the box sits from the edge of the display's visible frame.
    static let margin: CGFloat = 24

    private let panel: WidgetPanel
    private let dictation: GlobalDictation
    private let hint: () -> String
    private let voice: () -> VoiceLevels
    private let preferences: AppPreferences
    private var style = DictationWidgetStyle.medium
    private var livePreview = true
    private var position = DictationWidgetPosition.bottom
    private var theme = DictationWidgetTheme.accent
    private var spot: DictationWidgetSpot?
    private var area = CGRect.zero
    private var following = false
    private var hiding: Task<Void, Never>?

    init(dictation: GlobalDictation, preferences: AppPreferences, hint: @escaping () -> String, voice: @escaping () -> VoiceLevels) {
        self.dictation = dictation
        self.voice = voice
        self.preferences = preferences
        self.hint = hint
        panel = WidgetPanel(contentRect: .zero)
        // Esc on the text that was left open, which Carrier holds no hot key for: it is the panel's own while it is key
        panel.onEscape = { [unowned self] in self.dictation.dismissCopied() }
        panel.onDragged = { [unowned self] in self.dragged() }
    }

    func show() {
        hiding?.cancel()
        style = preferences.dictationWidgetStyle
        livePreview = preferences.dictationWidgetPreview
        position = preferences.dictationWidgetPosition
        theme = preferences.dictationWidgetTheme
        spot = preferences.dictationWidgetSpot
        if let screen = Self.activeScreen() { area = screen.visibleFrame }
        panel.ignoresMouseEvents = false
        panel.keyable = false
        if panel.isKeyWindow { panel.orderOut(nil) }
        let host = NSHostingView(rootView: DictationWidgetView(dictation: dictation, style: style, livePreview: livePreview, theme: theme, hint: hint, voice: voice).themed())
        // a theme that is dark or light draws its text so whatever the app's appearance is
        host.appearance = theme.appearance.map { NSAppearance(named: $0 == .light ? .aqua : .darkAqua) } ?? nil
        // the panel's size is `place()`'s alone: with the hosting view's own, a state with a scrolling text and buttons made the panel as tall as the display
        host.sizingOptions = []
        panel.contentView = host
        place()
        panel.orderFrontRegardless()
        follow()
    }

    /// The widget stays open for its buttons: it takes the keyboard (Tab, Return for Copy, Esc for Dismiss), still without activating Carrier.
    func takeClicks() {
        panel.keyable = true
        panel.makeKey()
    }

    /// A dictation that ended pasted or cancelled leaves its check or x for a moment, and the view fades it.
    func close() {
        hiding?.cancel()
        guard dictation.farewell != nil else { return panel.orderOut(nil) }
        let linger = dictationWidgetLook(dictation.shown, style: style, livePreview: livePreview).linger
        hiding = Task {
            try? await Task.sleep(for: .seconds(linger + Self.fade))
            if Task.isCancelled == false { panel.orderOut(nil) }
        }
    }

    private func place() {
        let look = dictationWidgetLook(dictation.shown, style: style, livePreview: livePreview)
        var size = look.windowSize
        if let box = look.box, case .copied(let reason) = dictation.state {
            // the notices over a text that was only copied take the lines they need, not a fixed number: a long reason wraps in a narrow box
            let textSize = TypeScale.stored().size(box.text)
            let notices = dictationKeptNotices(reason: reason, notCleaned: dictation.notCleaned)
            let wanted = Self.height(of: notices, size: textSize, width: box.width - 32)
            size.height += max(0, wanted - CGFloat(DictationWidgetBox.reasonLines) * box.lineHeight(textSize: textSize)).rounded(.up)
        }
        // never larger than the display leaves, whatever the state holds
        size.height = min(size.height, max(120, area.height - 2 * (Self.margin + Self.glow)))
        size.width = min(size.width, max(120, area.width - 2 * (Self.margin + Self.glow)))
        let box = NSRect(origin: dictationWidgetOrigin(size: size, in: area, position: position, margin: Self.margin, spot: spot), size: size)
        panel.setFrame(box.insetBy(dx: -Self.glow, dy: -Self.glow), display: true)
    }

    /// The person let go of the widget somewhere: that is where it opens from now on, on whichever display it was left, and it is put inside what the display leaves.
    private func dragged() {
        let centre = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(centre) }) { area = screen.visibleFrame }
        let kept = DictationWidgetSpot(frame: panel.frame.insetBy(dx: Self.glow, dy: Self.glow), in: area)
        spot = kept
        preferences.dictationWidgetSpot = kept
        place()
    }

    /// The height `lines` of text take at `size` points in `width`, one under the other with the 4 points between them that the box leaves.
    private static func height(of lines: [String], size: CGFloat, width: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: size)
        let heights = lines.map { line in
            (line as NSString).boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font]).height.rounded(.up)
        }
        return heights.reduce(0, +) + 4 * CGFloat(max(0, lines.count - 1))
    }

    /// Places the panel again each time what the widget shows changes the look (a Pill opens as the Small box for a text, a box grows to its buttons).
    private func follow() {
        guard following == false else { return }
        following = true
        withObservationTracking { _ = dictation.shown } onChange: { [weak self] in
            Task { @MainActor in self?.shownChanged() }
        }
    }

    private func shownChanged() {
        following = false
        guard panel.isVisible else { return }
        place()
        follow()
    }

    /// The display of the window in front, which macOS lists with no permission; the one with the pointer when that cannot be told.
    private static func activeScreen() -> NSScreen? {
        // Quartz puts its origin at the top left of the first display, AppKit at the bottom left
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let displays = NSScreen.screens.map { CGRect(x: $0.frame.minX, y: top - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height) }
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
            let frame = windows.first(where: { $0[kCGWindowOwnerPID as String] as? pid_t == pid && $0[kCGWindowLayer as String] as? Int == 0 })?[kCGWindowBounds as String] as? NSDictionary,
            let bounds = CGRect(dictionaryRepresentation: frame as CFDictionary), let index = displayIndex(of: bounds, in: displays)
        {
            return NSScreen.screens[index]
        }
        return NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first
    }
}

private final class WidgetPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    /// Whether it may take the keyboard: only while it holds a text that was copied and its buttons. That text is the person's to select, so then only the
    /// margins of the box move the panel (the system's drag); in every other state a drag anywhere in it does.
    var keyable = false {
        didSet { isMovableByWindowBackground = keyable }
    }
    var onEscape: (() -> Void)?
    /// Told when a drag ended somewhere else than it began.
    var onDragged: (() -> Void)?
    /// Where the pointer and the panel were when the button went down, for a drag of ours.
    private var grab: (pointer: NSPoint, origin: NSPoint)?
    private var dragging = false

    override var canBecomeKey: Bool { keyable }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) { onEscape?() }

    /// The events go where they would (a button, the scroll) and a drag that starts on the box also moves the panel, from three points on so a click does not nudge it.
    override func sendEvent(_ event: NSEvent) {
        let start = frame.origin
        super.sendEvent(event)
        switch event.type {
        case .leftMouseDown:
            grab = (NSEvent.mouseLocation, start)
            dragging = false
            // the system's own drag (the margins while it is key) ends inside this call
            if frame.origin != start { onDragged?() }
        case .leftMouseDragged:
            guard keyable == false, let grab else { return }
            let pointer = NSEvent.mouseLocation
            let (dx, dy) = (pointer.x - grab.pointer.x, pointer.y - grab.pointer.y)
            if dragging == false, hypot(dx, dy) < 3 { return }
            dragging = true
            setFrameOrigin(NSPoint(x: grab.origin.x + dx, y: grab.origin.y + dy))
        case .leftMouseUp:
            if dragging { onDragged?() }
            grab = nil
            dragging = false
        default: break
        }
    }
}
