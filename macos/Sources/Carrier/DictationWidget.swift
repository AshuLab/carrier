import AppKit
import CarrierCore
import SwiftUI

/// The widget of a global dictation: a panel that never takes the focus from the app the person is in (it is not main and does not activate Carrier,
/// and it is key only for the text that was left on it with its buttons) and lets every click through until it holds buttons. Its style and place are the person's (`AppPreferences.dictationWidgetStyle`
/// and `dictationWidgetPosition`, read each time it opens), its look for a state is `dictationWidgetLook`, and it follows `GlobalDictation.shown`,
/// resizing as the look changes. It is glass in the accent, and while it listens it draws the message box's line (`DictationIndicator`) around the box,
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
        // Esc on the text that was left open, which Carrier holds no hot key for: it is the panel's own while it is key
        panel.onEscape = { [unowned self] in self.dictation.dismissCopied() }
    }

    func show() {
        hiding?.cancel()
        style = preferences.dictationWidgetStyle
        position = preferences.dictationWidgetPosition
        if let screen = Self.activeScreen() { area = screen.visibleFrame }
        panel.ignoresMouseEvents = true
        panel.keyable = false
        if panel.isKeyWindow { panel.orderOut(nil) }
        let host = NSHostingView(rootView: DictationWidgetView(dictation: dictation, style: style, hint: hint, voice: voice))
        // the panel's size is `place()`'s alone: with the hosting view's own, a state with a scrolling text and buttons made the panel as tall as the display
        host.sizingOptions = []
        panel.contentView = host
        place()
        panel.orderFrontRegardless()
        follow()
    }

    /// The widget stays open for its buttons: it takes clicks and the keyboard (Tab, Return for Copy, Esc for Dismiss), still without activating Carrier.
    func takeClicks() {
        panel.ignoresMouseEvents = false
        panel.keyable = true
        panel.makeKey()
    }

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
        let look = dictationWidgetLook(dictation.shown, style: style)
        var size = look.windowSize
        if let box = look.box, case .copied(let reason) = dictation.state {
            // the notices over a text that was only copied take the lines they need, not a fixed number: a long reason wraps in a narrow box
            let textSize = TextSize.shared.scale.size(box.text)
            let notices = dictationKeptNotices(reason: reason, notCleaned: dictation.notCleaned)
            let wanted = Self.height(of: notices, size: textSize, width: box.width - 32)
            size.height += max(0, wanted - CGFloat(DictationWidgetBox.reasonLines) * box.lineHeight(textSize: textSize)).rounded(.up)
        }
        // never larger than the display leaves, whatever the state holds
        size.height = min(size.height, max(120, area.height - 2 * (Self.margin + Self.glow)))
        size.width = min(size.width, max(120, area.width - 2 * (Self.margin + Self.glow)))
        let box = NSRect(origin: dictationWidgetOrigin(size: size, in: area, position: position, margin: Self.margin), size: size)
        panel.setFrame(box.insetBy(dx: -Self.glow, dy: -Self.glow), display: true)
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

    /// Whether it may take the keyboard: only while it holds a text that was copied and its buttons.
    var keyable = false
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { keyable }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) { onEscape?() }
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
        // the panel is not in front of VoiceOver, so what it cannot be told to read is said
        .onChange(of: dictation.shown) { _, shown in
            switch (shown, dictation.state) {
            case (.copied, .copied(let reason)): AccessibilityNotification.Announcement("\(reason.explanation) It is on the clipboard.").post()
            case (.failed, .failed(let cause)): AccessibilityNotification.Announcement("Dictation failed: \(cause)").post()
            case (.pastedRaw, _): AccessibilityNotification.Announcement("Pasted without cleaning: \(dictation.notCleaned ?? "")").post()
            default: break
            }
        }
        .task(id: look.fades) {
            faded = false
            guard look.fades else { return }
            try? await Task.sleep(for: .seconds(look.linger))
            // a state that changed during the wait cancels the task, and the widget has not ended
            guard Task.isCancelled == false else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: DictationWidget.fade)) { faded = true }
        }
    }

    @ViewBuilder private func boxed(_ look: DictationWidgetLook, _ box: DictationWidgetBox) -> some View {
        if case .copied(let reason) = dictation.state {
            WidgetBox(box: box, follows: false, notices: keptNotices(reason)) { Text(dictation.text).textSelection(.enabled) } foot: { keptButtons(reason) }
        } else if case .failed = dictation.state {
            // nothing is running: no clock and no finish key, only the way out
            WidgetBox(box: box) { shown } foot: {
                Spacer()
                Text("Esc to dismiss")
            }
        } else if look.fades {
            WidgetBox(box: box) { Text(dictation.text) } foot: {
                switch dictation.farewell {
                case .pasted: Label("Pasted", icon: .check)
                case .pastedRaw: Label("Pasted without cleaning: \(dictation.notCleaned ?? "")", icon: .warning).foregroundStyle(.orange).lineLimit(1)
                default: Label("Cancelled", icon: .close)
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
                if dictation.shown == .cleaning { Label("Cleaning… Esc to skip", icon: .sparkles) } else { Text(hint()) }
            }
        }
    }

    /// Why the text was only copied, over the text, which is complete and scrolls under them.
    private func keptNotices(_ reason: PasteReason) -> [String] { dictationKeptNotices(reason: reason, notCleaned: dictation.notCleaned) }

    /// The buttons of a text that was only copied; when they do not fit the box's width they keep only their symbols.
    private func keptButtons(_ reason: PasteReason) -> some View {
        ViewThatFits(in: .horizontal) {
            keptRow(reason).labelStyle(.titleAndIcon)
            keptRow(reason).labelStyle(.iconOnly)
        }
        .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
    }

    private func keptRow(_ reason: PasteReason) -> some View {
        HStack {
            if reason == .noPermission {
                Button { FocusedField.openSettings() } label: { Label("Open System Settings", icon: .settings) }
                Button { FocusedField.resetPermission() } label: { Label("Reset permission", icon: .refresh) }
                    .help("Already allowed in System Settings? macOS drops the permission when Carrier updates. This removes it and asks again.")
            }
            Spacer()
            Button {
                dictation.copyAgain()
                copied = true
            } label: { Label(copied ? "Copied" : "Copy", icon: copied ? .check : .copy) }
            .keyboardShortcut(.defaultAction)
            Button { dictation.dismissCopied() } label: { Label("Dismiss", icon: .close) }
        }
    }

    /// What was heard: the firm words as normal text and the tentative ones in the partial colour with the dotted underline, as the message box draws them.
    private var heard: Text {
        let (firm, tentative) = dictation.split
        return Text("\(firm)\(Text(tentative).foregroundStyle(Color(nsColor: PillTextView.tentativeColor)).underline(pattern: .dot))")
    }

    /// What the box says before the words come, and the cause when it cannot go on, over what was heard.
    @ViewBuilder private var shown: some View {
        let caption = dictationPresentation(
            dictation.session.state, registered: true, modelReady: dictation.session.modelReady, answerIsSlow: dictation.session.answerIsSlow
        )?.caption
        VStack(alignment: .leading, spacing: 4) {
            if case .failed(let cause) = dictation.state { Text(cause).foregroundStyle(.red) }
            if dictation.text.isEmpty == false {
                // the raw text shimmers while the model cleans it
                heard.modifier(Shimmer(active: dictation.shown == .cleaning && reduceMotion == false))
            } else if dictation.state == .running, let caption {
                Text(caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// A box of the widget: the text at the top, a row under it, and when the text is longer than the lines of the style it scrolls so the newest words
/// are on the last line, with the older lines fading out at the top (`dictationTextFit`). A `follows: false` box (the text that was only copied)
/// starts at the top and is the person's to scroll, with no fade and with its scroll bar showing, under the `notices` (a reason, in orange), which
/// stay where they are.
struct WidgetBox<Content: View, Foot: View>: View {
    let box: DictationWidgetBox
    var follows = true
    var notices: [String] = []
    @ViewBuilder var text: Content
    @ViewBuilder var foot: Foot
    @State private var position = ScrollPosition(edge: .top)
    @State private var textLines = 0

    var body: some View {
        let lineHeight = box.lineHeight(textSize: TextSize.shared.scale.size(box.text))
        let fadesTop = follows && dictationTextFit(textLines: textLines, boxLines: box.lines).fadesTop
        VStack(alignment: .leading, spacing: 8) {
            if notices.isEmpty == false {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(notices, id: \.self) { Text($0).foregroundStyle(.orange) }
                }
                .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            }
            ScrollView {
                text.frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(follows ? .hidden : .visible)
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
            HStack { foot }.font(.scaled(11)).foregroundStyle(.secondary).frame(height: 20)
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
            Glyph(.sparkles, label: "Cleaning").foregroundStyle(Color.themeAccent).glyphPulsing(reduceMotion == false)
        case .warning:
            Glyph(.warningFilled, label: "Pasted without cleaning: \(cause ?? "")").foregroundStyle(.orange)
        case .mic: Glyph(.microphone, label: "Listening").foregroundStyle(Color.themeAccent)
        case .spinner: ProgressView().controlSize(.small).accessibilityLabel("Working")
        case .check: Glyph(.check, label: "Pasted").foregroundStyle(.green)
        case .xmark: Glyph(.close, label: "Cancelled").foregroundStyle(.secondary)
        }
    }
}

/// The chosen style as the Dictation page shows it, listening to a sample.
struct DictationWidgetPreview: View {
    let style: DictationWidgetStyle
    let hint: String
    /// The width the page gives it, so the Large box (540) shrinks to fit a narrow window instead of overflowing the card.
    @State private var available = CGFloat.infinity

    var body: some View {
        let look = dictationWidgetLook(.listening, style: style)
        let scale = min(1, available / look.windowSize.width)
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
        .scaleEffect(scale)
        .frame(width: look.windowSize.width * scale, height: look.windowSize.height * scale)
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { available = $0 }
        .accessibilityElement(children: .ignore).accessibilityLabel("Preview of the \(style.title) widget")
    }

    private static let sample = "I need you to send me the summary of yesterday's meeting with the action points, and also each team's list of pending items"
}
