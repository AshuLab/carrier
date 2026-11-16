import AppKit
import CarrierCore
import SwiftUI

/// The widget of a global dictation: a panel that never takes the focus from the app the person is in (it is not key, not main and does not
/// activate Carrier) and lets every click through. This is the plain Small box: the text, the time, the shortcut and Esc.
@MainActor final class DictationWidget {
    private static let width: CGFloat = 340
    private static let height: CGFloat = 96
    private static let margin: CGFloat = 24

    private let panel: NSPanel

    init(dictation: GlobalDictation, shortcut: String) {
        panel = WidgetPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.height))
        panel.contentView = NSHostingView(rootView: DictationWidgetView(dictation: dictation, shortcut: shortcut).frame(width: Self.width, height: Self.height))
    }

    func show() {
        let area = Self.activeScreen().visibleFrame
        panel.setFrameOrigin(NSPoint(x: area.midX - Self.width / 2, y: area.minY + Self.margin))
        panel.orderFrontRegardless()
    }

    func close() { panel.orderOut(nil) }

    /// The display of the window in front, which macOS lists with no permission; the one with the pointer when that cannot be told.
    private static func activeScreen() -> NSScreen {
        // Quartz puts its origin at the top left of the first display, AppKit at the bottom left
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let displays = NSScreen.screens.map { CGRect(x: $0.frame.minX, y: top - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height) }
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
            let frame = windows.first(where: { $0[kCGWindowOwnerPID as String] as? pid_t == pid && $0[kCGWindowLayer as String] as? Int == 0 })?[kCGWindowBounds as String],
            let bounds = CGRect(dictionaryRepresentation: frame as! CFDictionary), let index = displayIndex(of: bounds, in: displays)
        {
            return NSScreen.screens[index]
        }
        return NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
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

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct DictationWidgetView: View {
    let dictation: GlobalDictation
    let shortcut: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                shown.frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden).defaultScrollAnchor(.bottom)
            HStack {
                if let started = dictation.startedAt {
                    TimelineView(.periodic(from: started, by: 1)) { context in
                        Text(dictationClock(context.date.timeIntervalSince(started))).monospacedDigit()
                    }
                }
                Spacer()
                Text("\(shortcut) to finish · Esc to cancel")
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .chatSurface(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// What the box says before the words come, and the cause when it cannot go on, over what was heard.
    @ViewBuilder private var shown: some View {
        let caption = dictationPresentation(dictation.session.state, registered: true)?.caption
        VStack(alignment: .leading, spacing: 4) {
            if case .failed(let cause) = dictation.state { Text(cause).foregroundStyle(.red) }
            if dictation.text.isEmpty == false {
                Text(dictation.text)
            } else if dictation.state == .running, let caption {
                Text(caption).foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }
}
