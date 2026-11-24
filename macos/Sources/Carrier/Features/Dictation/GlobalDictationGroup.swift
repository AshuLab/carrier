import AppKit
import CarrierCore
import SwiftUI

/// The Global dictation group of the page: Dictate in any app (the switch of the shortcut that opens the widget in any app), Accessibility, the Shortcut
/// and how it starts. With Dictation off the group is drawn at 40%. The widget's own settings are the next group (`WidgetGroup`).
struct GlobalDictationGroup: View {
    var dictation = DictationController.shared
    // the preference is read and written by the switch; this makes the group redraw when Reset changes it
    @AppStorage(Preference.dictationGlobal) private var global
    @AppStorage(Preference.dictationAccessibilityExplained) private var explained
    @AppStorage(Preference.dictationShortcut) private var shortcutText
    @AppStorage(Preference.dictationActivation) private var activation
    @State private var explaining = false
    /// What macOS says now; it is asked again each time Carrier comes back to the front, since the person allows it in System Settings.
    @State private var accessibility = AccessibilityState(trust: SystemAccessibilityTrust())

    var body: some View {
        SettingsGroup(title: "Global dictation", footer: "The first time you turn it on, Carrier explains what Accessibility is for before macOS asks.") {
            SettingsTabRow(
                title: "Dictate in any app",
                detail: "\(AppPreferences().dictationShortcut.text) opens a widget in any app, and pastes what you said at the cursor",
                first: true
            ) {
                Toggle("Dictate in any app", isOn: switchBinding).labelsHidden().toggleStyle(.switch)
            }
            .live(.globalSwitch, enabled: dictation.enabled)
            Group {
                accessibilityRow
                ShortcutRecorderRow(
                    shortcutText: shortcutText, title: "Shortcut", detail: "With Carrier in front on a session it dictates into the message box, with no widget",
                    name: "Dictation shortcut",
                    current: { AppPreferences().dictationShortcut }, save: { AppPreferences().dictationShortcut = $0 ?? .standard },
                    taken: { $0 == AppPreferences().awakeShortcut ? "Keep awake uses these keys" : nil })
                SettingsTabRow(title: "Activation", detail: "Toggle: press to start, press again to finish. Hold: speak while the keys are down") {
                    SegmentedChoice(options: [(DictationActivation.toggle, "Toggle", nil), (.hold, "Hold", nil)], selection: $activation).accessibilityLabel("Activation")
                }
            }
            .live(.globalSwitch, enabled: dictation.enabled && global)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in accessibility.refresh() }
        .alert("Carrier needs Accessibility", isPresented: $explaining) {
            Button("Continue") {
                explained = true
                // macOS asks, and lists Carrier in Privacy & Security › Accessibility for the person to allow
                accessibility.ask()
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text(
                "To paste what you say into the app you are in, Carrier needs to see which field has the cursor, and to press ⌘V for you. "
                    + "It never reads what is in the fields, and it does not paste into password fields. Without it, the text goes on the clipboard instead.")
        }
    }

    private var accessibilityRow: some View {
        SettingsTabRow(
            title: "Accessibility",
            detail: accessibility.trusted
                ? "Carrier can see which field has the cursor and paste into it"
                : "Without it the text goes on the clipboard instead of being pasted. Already allowed? macOS drops it when Carrier updates: reset it"
        ) {
            HStack(spacing: 8) {
                StatusChip(text: accessibility.trusted ? "Allowed" : "Not allowed", tint: accessibility.trusted ? .green : .orange)
                Button { FocusedField.openSettings() } label: { Label("Open System Settings", icon: .settings) }
                    .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
                if accessibility.trusted == false {
                    Button { FocusedField.resetPermission() } label: { Label("Reset", icon: .refresh) }
                        .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small).help("Removes Carrier from Accessibility and asks again")
                }
            }
        }
    }

    /// Turning it on the first time explains what Accessibility is for before macOS asks.
    private var switchBinding: Binding<Bool> {
        Binding(
            get: { global },
            set: {
                global = $0
                explaining = $0 && accessibility.shouldExplain(explained: explained)
            })
    }
}

/// The Widget group: how the widget looks (its style and its theme, each seen as a small drawing, and whether it shows the words) and where it opens (a place, or
/// where the person dragged it), with a preview of the chosen look listening to a sample, right under what changes it. Drawn at 40% while Dictation or Dictate in
/// any app is off.
struct WidgetGroup: View {
    var dictation = DictationController.shared
    @AppStorage(Preference.dictationGlobal) private var global
    @AppStorage(Preference.dictationActivation) private var activation
    @AppStorage(Preference.dictationWidgetStyle) private var widgetStyle
    @AppStorage(Preference.dictationWidgetPosition) private var widgetPosition
    @AppStorage(Preference.dictationWidgetTheme) private var widgetTheme
    @AppStorage(Preference.dictationWidgetPreview) private var livePreview
    @AppStorage(Preference.dictationWidgetSpot) private var spotText
    @AppStorage(Preference.dictationShortcut) private var shortcutText

    /// What the Position row chooses among: the two places, and Custom while the person has dragged the widget somewhere.
    private enum Place: Hashable { case top, bottom, custom }

    var body: some View {
        SettingsGroup(title: "Widget") {
            SettingsStackedRow(title: "Widget style", detail: "Pill is a badge with a microphone and no text; Small, Medium and Large are a box of 2, 3 and 4 lines", first: true) {
                WidgetStylePicker(selection: $widgetStyle)
            }
            SettingsStackedRow(title: "Widget theme", detail: "Default takes the app's accent. Theme glow wears the colours of the dictation line") {
                WidgetThemePicker(selection: $widgetTheme)
            }
            SettingsTabRow(title: "Live text", detail: "Show the words as you say them. Off, the widget keeps its box with the time and the keys, and no words") {
                Toggle("Live text", isOn: $livePreview).labelsHidden().toggleStyle(.switch)
            }
            SettingsTabRow(title: "Position", detail: "Top or bottom centre, on the display of the window in front. Drag the widget while you dictate to leave it anywhere") {
                SegmentedChoice(options: places, selection: place).accessibilityLabel("Widget position")
            }
            SettingsPreview {
                DictationWidgetPreview(
                    style: widgetStyle, theme: widgetTheme, livePreview: livePreview, hint: dictationHint(shortcut: AppPreferences().dictationShortcut, activation: activation))
            }
        }
        .live(.globalSwitch, enabled: dictation.enabled && global)
    }

    private var places: [(Place, String, AppIcon?)] {
        [(.top, "Top", nil), (.bottom, "Bottom", nil)] + (DictationWidgetSpot(text: spotText ?? "") == nil ? [] : [(.custom, "Custom", nil)])
    }

    /// Choosing Top or Bottom lets go of the spot the widget was dragged to; Custom is only what it reads while there is one.
    private var place: Binding<Place> {
        Binding(
            get: { DictationWidgetSpot(text: spotText ?? "") == nil ? (widgetPosition == .top ? .top : .bottom) : .custom },
            set: {
                switch $0 {
                case .top: widgetPosition = .top
                case .bottom: widgetPosition = .bottom
                case .custom: return
                }
                spotText = nil
            })
    }
}

/// The five themes of the widget as five small drawings over a backdrop that shows the glass, the chosen one with the accent's edge and its words under it.
private struct WidgetThemePicker: View {
    @Binding var selection: DictationWidgetTheme

    var body: some View {
        HStack(spacing: 10) {
            ForEach(DictationWidgetTheme.allCases, id: \.self) { theme in
                let on = theme == selection
                Button { selection = theme } label: {
                    VStack(spacing: 8) {
                        swatch(theme).frame(height: 44)
                        Text(theme.title).font(.scaled(11, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .padding(.vertical, 10).padding(.horizontal, 6).frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? Color.themeAccent.opacity(0.16) : Color.primary.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.themeAccent, lineWidth: on ? 1.5 : 0))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel(theme.title).accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain).accessibilityLabel("Widget theme")
    }

    /// The widget's own surface over a bright backdrop, with a microphone in the way its text would be drawn.
    private func swatch(_ theme: DictationWidgetTheme) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return ZStack {
            shape.fill(LinearGradient(colors: [.pink.opacity(0.7), .orange.opacity(0.7), .teal.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Glyph(.microphone, size: 14).foregroundStyle(theme == .clear ? Color.primary.opacity(0.8) : Color.white.opacity(0.9))
                .frame(width: 34, height: 22)
                .modifier(WidgetSurface(shape: RoundedRectangle(cornerRadius: 7, style: .continuous), theme: theme))
        }
        .frame(maxWidth: .infinity).clipShape(shape)
    }
}

/// The four styles of the widget as four small drawings, the chosen one with the accent's edge: the words of the style under each, and the drawing says
/// what the words only count (a badge, then a box of two, three and four lines).
private struct WidgetStylePicker: View {
    @Binding var selection: DictationWidgetStyle

    var body: some View {
        HStack(spacing: 10) {
            ForEach(DictationWidgetStyle.allCases, id: \.self) { style in
                let on = style == selection
                Button { selection = style } label: {
                    VStack(spacing: 8) {
                        drawing(style).frame(height: 44)
                        Text(style.title).font(.scaled(12, weight: .medium))
                    }
                    .padding(.vertical, 10).frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? Color.themeAccent.opacity(0.16) : Color.primary.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.themeAccent, lineWidth: on ? 1.5 : 0))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel(style.title).accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain).accessibilityLabel("Widget style")
    }

    @ViewBuilder private func drawing(_ style: DictationWidgetStyle) -> some View {
        let lines = dictationWidgetLook(.listening, style: style).box?.lines
        if let lines {
            VStack(spacing: 4) {
                ForEach(0..<lines, id: \.self) { _ in Capsule().fill(Color.white.opacity(0.6)).frame(height: 3) }
            }
            .padding(.horizontal, 8).padding(.vertical, 7).frame(width: 74)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.themeAccent.opacity(0.75)))
        } else {
            Capsule().fill(Color.themeAccent.opacity(0.75)).frame(width: 36, height: 18)
        }
    }
}

/// The row that records a global shortcut, the same for Dictation's and Keep awake's: the keys shown, Record to press new ones (Esc or Cancel keeps the old),
/// the reason when a combination is refused, and, with `emptyText`, Clear for a shortcut that may be none. While it listens both global shortcuts are let go,
/// so pressing either records it instead of running it. `shortcutText` makes the row draw again when the saved shortcut changes; `problem` is why a recorded
/// shortcut is not registered; `taken` says why a combination is refused because another feature has it.
struct ShortcutRecorderRow: View {
    let shortcutText: String
    let title: String
    let detail: String
    let name: String
    /// What is shown when nothing is recorded; nil for a shortcut that always has keys (the dictation's).
    var emptyText: String?
    var problem: String?
    let current: () -> DictationShortcut?
    let save: (DictationShortcut?) -> Void
    let taken: (DictationShortcut) -> String?
    @State private var recording = false
    @State private var monitor: Any?
    @State private var refusal: String?

    var body: some View {
        let shown = current()?.text ?? emptyText ?? ""
        SettingsTabRow(title: title, detail: detail, problem: refusal ?? problem) {
            HStack(spacing: 8) {
                Text(recording ? "Press the keys…" : shown)
                    .font(.scaled(12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(recording ? Color.themeAccent : Color.primary)
                    .frame(minWidth: 96).padding(.horizontal, 10).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(recording ? 0.12 : 0.08)))
                    .overlay { if recording { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.themeAccent, lineWidth: 1.5) } }
                    .accessibilityLabel(name).accessibilityValue(recording ? "Listening for the new keys" : shown)
                Button { recording ? stop() : start() } label: { Label(recording ? "Cancel" : "Record", icon: recording ? .close : .record) }
                    .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
                if emptyText != nil, current() != nil, recording == false {
                    Button {
                        refusal = nil
                        save(nil)
                        AccessibilityNotification.Announcement("\(name) cleared").post()
                    } label: { Label("Clear", icon: .close) }
                        .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small).accessibilityLabel("Clear the \(name.lowercased())")
                }
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        refusal = nil
        recording = true
        AccessibilityNotification.Announcement("Press the new keys, or Escape to cancel").post()
        Self.listening(true)
        // the next key comes here and not to the window's shortcuts: this monitor sees it first, and it is not passed on
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Esc cancels, and a combination with no modifier is told why it was refused and the recorder keeps listening
            guard event.keyCode != 53 else { stop(); return nil }
            switch recordShortcut(keyCode: Int(event.keyCode), characters: event.charactersIgnoringModifiers ?? "", modifiers: .init(event.modifierFlags)) {
            case .accepted(let shortcut):
                // the other feature's keys are refused: two shortcuts on one combination would run only one of them
                if let reason = taken(shortcut) {
                    refusal = reason
                    AccessibilityNotification.Announcement(reason).post()
                    return nil
                }
                save(shortcut)
                stop()
                AccessibilityNotification.Announcement("Shortcut set to \(shortcut.text)").post()
            case .refused(let reason):
                refusal = reason
                // a row's problem is not read aloud by itself
                AccessibilityNotification.Announcement(reason).post()
            }
            return nil
        }
    }

    private func stop() {
        // the row going off screen calls this too: with nothing recorded there is nothing to let go or to forget
        guard recording || monitor != nil else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        refusal = nil
        Self.listening(false)
    }

    /// Both global shortcuts are let go while a row listens, so the keys of either can be recorded in either row.
    private static func listening(_ on: Bool) {
        GlobalDictationController.shared.recording = on
        KeepAwakeController.shared.recordingShortcut = on
    }
}
