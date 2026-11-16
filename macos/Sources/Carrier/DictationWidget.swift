import AppKit
import CarrierCore
import SwiftUI

/// The widget of a global dictation: a panel that never takes the focus from the app the person is in (it is not key, not main and does not
/// activate Carrier) and lets every click through. This is the plain Small box: the text, the time, the shortcut and Esc.
@MainActor final class DictationWidget {
    private static let width: CGFloat = 340
    private static let height: CGFloat = 96
    /// The box left open with the text and its buttons.
    private static let keptHeight: CGFloat = 190
    private static let margin: CGFloat = 24

    private let panel: NSPanel

    init(dictation: GlobalDictation, hint: @escaping () -> String) {
        panel = WidgetPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.height))
        panel.contentView = NSHostingView(rootView: DictationWidgetView(dictation: dictation, hint: hint))
    }

    func show() {
        let area = Self.activeScreen().visibleFrame
        panel.ignoresMouseEvents = true
        panel.setFrame(NSRect(x: area.midX - Self.width / 2, y: area.minY + Self.margin, width: Self.width, height: Self.height), display: true)
        panel.orderFrontRegardless()
    }

    /// The widget stays open for its buttons: taller, growing upward from where it is, and it takes clicks (still without taking the focus).
    func takeClicks() {
        panel.ignoresMouseEvents = false
        panel.setFrame(NSRect(origin: panel.frame.origin, size: NSSize(width: Self.width, height: Self.keptHeight)), display: true)
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
    /// The keys line: what ends the dictation and Esc.
    let hint: () -> String
    /// Copy was pressed; it goes back when the widget has new text.
    @State private var copied = false

    var body: some View {
        Group {
            if case .copied(let reason) = dictation.state { kept(reason) } else { listening }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .chatSurface(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .onChange(of: dictation.state) { copied = false }
    }

    private var listening: some View {
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
                Text(hint())
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// The text that was only copied, complete and scrollable, why, and what the person can do about it.
    private func kept(_ reason: PasteReason) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(reason.explanation) It is on the clipboard.").foregroundStyle(.orange)
                    Text(dictation.text).textSelection(.enabled)
                }
                .font(.callout).frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                if reason == .noPermission {
                    Button("Open System Settings") {
                        if let url = URL(string: FocusedField.settingsURL) { NSWorkspace.shared.open(url) }
                    }
                }
                Spacer()
                Button(copied ? "Copied" : "Copy") {
                    dictation.copyAgain()
                    copied = true
                }
                Button("Dismiss") { dictation.dismissCopied() }
            }
            .buttonStyle(.bordered).controlSize(.small)
        }
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
