import AppKit
import CarrierCore
import SwiftUI

/// The widget of a global dictation: a panel that never takes the focus from the app the person is in (it is not key, not main and does not
/// activate Carrier) and lets every click through until it holds buttons. Its style and place are the person's (`AppPreferences.dictationWidgetStyle`
/// and `dictationWidgetPosition`, read each time it opens), its look for a state is `dictationWidgetLook`, and it follows `GlobalDictation.shown`,
/// resizing as the look changes. It is glass in the accent, and while it listens it draws the message box's line (`DictationIndicator`) around the box,
/// which is why the panel is `glow` points larger than the box on each side. It holds the text, the time, the shortcut and Esc.
@MainActor final class DictationWidget {
    /// How long it takes the check, the warning or the x to fade (how long they stay is `DictationWidgetLook.linger`).
    static let fade = 0.3
    /// The room the listening line and the shadow have around the box, inside the panel.
    static let glow: CGFloat = 14

    private let panel: NSPanel
    private let dictation: GlobalDictation
    private let hint: () -> String
    private let voice: () -> VoiceLevels
    private let preferences: AppPreferences
    private var style = DictationWidgetStyle.medium
    private var position = DictationWidgetPosition.bottom
    private var area = CGRect.zero
    private var following = false
    private var hiding: Task<Void, Never>?

    init(dictation: GlobalDictation, preferences: AppPreferences, hint: @escaping () -> String, voice: @escaping () -> VoiceLevels) {
        self.dictation = dictation
        self.voice = voice
        self.preferences = preferences
        self.hint = hint
        panel = WidgetPanel(contentRect: .zero)
    }

    func show() {
        hiding?.cancel()
        style = preferences.dictationWidgetStyle
        position = preferences.dictationWidgetPosition
        area = Self.activeScreen().visibleFrame
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: DictationWidgetView(dictation: dictation, style: style, hint: hint, voice: voice))
        place()
        panel.orderFrontRegardless()
        follow()
    }

    /// The widget stays open for its buttons, and takes clicks (still without taking the focus).
    func takeClicks() { panel.ignoresMouseEvents = false }

    /// A dictation that ended pasted or cancelled leaves its check or x for a moment, and the view fades it.
    func close() {
        hiding?.cancel()
        guard dictation.farewell != nil else { return panel.orderOut(nil) }
        let linger = dictationWidgetLook(dictation.shown, style: style).linger
        hiding = Task {
            try? await Task.sleep(for: .seconds(linger + Self.fade))
            if Task.isCancelled == false { panel.orderOut(nil) }
        }
    }

    private func place() {
        let size = dictationWidgetLook(dictation.shown, style: style).windowSize
        let box = NSRect(origin: dictationWidgetOrigin(size: size, in: area, position: position), size: size)
        panel.setFrame(box.insetBy(dx: -Self.glow, dy: -Self.glow), display: true)
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

extension DictationWidgetLook {
    /// The window's size: the Pill's, or the box's at the person's text size.
    var windowSize: CGSize {
        guard let box else { return Self.pillSize }
        return CGSize(width: box.width, height: box.height(textSize: TextSize.shared.scale.size(box.text)))
    }

    /// The Pill is a capsule and a box has the message box's radius.
    var radius: CGFloat { box == nil ? windowSize.height / 2 : 16 }
    var shape: RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }
}

/// The widget's glass: the chat's surface tinted with the app's accent, a light veil of it over a light window and a dark one over a dark window so the
/// text reads over a white window too, and a soft shadow since the panel has none of its own.
private struct WidgetSurface: ViewModifier {
    let shape: RoundedRectangle
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let tint = scheme == .dark ? Color.themeAccent.mix(with: .black, by: 0.6).opacity(0.55) : Color.themeAccent.opacity(0.12)
        content.chatSurface(.regular.tint(tint), flat: tint, in: shape).shadow(color: .black.opacity(0.22), radius: 10, y: 3)
    }
}

private struct DictationWidgetView: View {
    let dictation: GlobalDictation
    let style: DictationWidgetStyle
    /// The keys line: what ends the dictation and Esc.
    let hint: () -> String
    let voice: () -> VoiceLevels
    /// Copy was pressed; it goes back when the widget has new text.
    @State private var copied = false
    /// The check or x of a dictation that ended has faded.
    @State private var faded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let look = dictationWidgetLook(dictation.shown, style: style)
        Group {
            if let box = look.box { boxed(look, box) } else if let icon = look.icon { PillIcon(icon: icon, cause: dictation.notCleaned) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // the message box's line, outside the box and only while it listens
        .background {
            if dictation.shown == .listening { DictationIndicator(levels: voice(), radius: look.radius) }
        }
        .modifier(WidgetSurface(shape: look.shape))
        .opacity(faded ? 0 : 1)
        .padding(DictationWidget.glow)
        .accessibilityElement(children: .contain)
        .onChange(of: dictation.state) { copied = false }
        .task(id: look.fades) {
            faded = false
            guard look.fades else { return }
            try? await Task.sleep(for: .seconds(look.linger))
            withAnimation(reduceMotion ? nil : .easeOut(duration: DictationWidget.fade)) { faded = true }
        }
    }

    @ViewBuilder private func boxed(_ look: DictationWidgetLook, _ box: DictationWidgetBox) -> some View {
        if case .copied(let reason) = dictation.state {
            WidgetBox(box: box, follows: false) { keptText(reason) } foot: { keptButtons(reason) }
        } else if look.fades {
            WidgetBox(box: box) { Text(dictation.text) } foot: {
                switch dictation.farewell {
                case .pasted: Label("Pasted", systemImage: "checkmark")
                case .pastedRaw: Label("Pasted without cleaning: \(dictation.notCleaned ?? "")", systemImage: "exclamationmark.triangle").foregroundStyle(.orange).lineLimit(1)
                default: Label("Cancelled", systemImage: "xmark")
                }
            }
        } else {
            WidgetBox(box: box) { shown } foot: {
                if let started = dictation.startedAt {
                    TimelineView(.periodic(from: started, by: 1)) { context in
                        Text(dictationClock(context.date.timeIntervalSince(started))).monospacedDigit()
                    }
                }
                Spacer()
                if dictation.shown == .cleaning { Label("Cleaning… Esc to skip", systemImage: "sparkles") } else { Text(hint()) }
            }
        }
    }

    /// Why the text was only copied, and the text, complete (the box scrolls).
    private func keptText(_ reason: PasteReason) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(reason.explanation) It is on the clipboard.").foregroundStyle(.orange)
            if let cause = dictation.notCleaned { Text("It was not cleaned: \(cause)").foregroundStyle(.orange) }
            Text(dictation.text).textSelection(.enabled)
        }
    }

    private func keptButtons(_ reason: PasteReason) -> some View {
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

    /// What the box says before the words come, and the cause when it cannot go on, over what was heard.
    @ViewBuilder private var shown: some View {
        let caption = dictationPresentation(dictation.session.state, registered: true)?.caption
        VStack(alignment: .leading, spacing: 4) {
            if case .failed(let cause) = dictation.state { Text(cause).foregroundStyle(.red) }
            if dictation.text.isEmpty == false {
                // the raw text shimmers while the model cleans it
                Text(dictation.text).modifier(Shimmer(active: dictation.shown == .cleaning && reduceMotion == false))
            } else if dictation.state == .running, let caption {
                Text(caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// A box of the widget: the text at the top, a row under it, and when the text is longer than the lines of the style it scrolls so the newest words
/// are on the last line, with the older lines fading out at the top (`dictationTextFit`). A `follows: false` box (the text that was only copied)
/// starts at the top and is the person's to scroll, with no fade.
struct WidgetBox<Content: View, Foot: View>: View {
    let box: DictationWidgetBox
    var follows = true
    @ViewBuilder var text: Content
    @ViewBuilder var foot: Foot
    @State private var position = ScrollPosition(edge: .top)
    @State private var textLines = 0

    var body: some View {
        let lineHeight = box.lineHeight(textSize: TextSize.shared.scale.size(box.text))
        let fadesTop = follows && dictationTextFit(textLines: textLines, boxLines: box.lines).fadesTop
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                text.frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .scrollPosition($position)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height } action: { _, height in
                guard follows else { return }
                textLines = Int((height / lineHeight).rounded())
                if dictationTextFit(textLines: textLines, boxLines: box.lines).fadesTop { position.scrollTo(edge: .bottom) }
            }
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: fadesTop ? lineHeight : 0)
                    Rectangle()
                }
            }
            HStack { foot }.font(.caption).foregroundStyle(.secondary).frame(height: 20)
        }
        .font(.scaled(box.text))
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}

/// The Pill's icon: the microphone in the accent while it listens, a spinner while it works, a sparkle while it cleans, a check when pasted, a warning
/// when it pasted without cleaning (`cause` says why, for VoiceOver) and an x when cancelled.
private struct PillIcon: View {
    let icon: DictationWidgetIcon
    var cause: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch icon {
        case .sparkle:
            Image(systemName: "sparkles").foregroundStyle(Color.themeAccent).symbolEffect(.pulse, isActive: reduceMotion == false).accessibilityLabel("Cleaning")
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).accessibilityLabel("Pasted without cleaning: \(cause ?? "")")
        case .mic: Image(systemName: "mic.fill").foregroundStyle(Color.themeAccent).accessibilityLabel("Listening")
        case .spinner: ProgressView().controlSize(.small).accessibilityLabel("Working")
        case .check: Image(systemName: "checkmark").foregroundStyle(.green).accessibilityLabel("Pasted")
        case .xmark: Image(systemName: "xmark").foregroundStyle(.secondary).accessibilityLabel("Cancelled")
        }
    }
}

/// The chosen style as the Dictation page shows it, listening to a sample.
struct DictationWidgetPreview: View {
    let style: DictationWidgetStyle
    let hint: String

    var body: some View {
        let look = dictationWidgetLook(.listening, style: style)
        Group {
            if let box = look.box {
                WidgetBox(box: box) { Text(Self.sample) } foot: {
                    Text("0:12").monospacedDigit()
                    Spacer()
                    Text(hint)
                }
            } else {
                PillIcon(icon: .mic)
            }
        }
        .frame(width: look.windowSize.width, height: look.windowSize.height)
        .modifier(WidgetSurface(shape: look.shape))
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore).accessibilityLabel("Preview of the \(style.title) widget")
    }

    private static let sample = "I need you to send me the summary of yesterday's meeting with the action points, and also each team's list of pending items"
}
