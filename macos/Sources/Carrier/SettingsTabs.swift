import AppKit
import CarrierCore
import ServiceManagement
import SwiftUI

// The page pattern of Settings (a header, cards of rows, a preview, a Reset) and the General and Notifications pages.

/// A row of these tabs: a title and a line under it on the left, the control on the right.
struct SettingsTabRow<Control: View>: View {
    let title: String
    let detail: String
    var first = false
    var mono = false
    /// More room above and below, for a form with many fields stacked; the line between rows stays halfway.
    var roomy = false
    /// A third line for what the row is and not what it says (a path, a login): monospaced and quieter than the detail.
    var note: String?
    /// What is wrong with the value, in words: it takes the place of the detail, in orange and with a warning mark, the title keeps its colour, and
    /// every `settingsField` and `NumberField` inside the row draws itself as invalid (`\.settingsInvalid`). One argument; nothing else to pass.
    var problem: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).fontWeight(.medium)
                if detail.isEmpty == false || problem != nil {
                    Group {
                        if let problem { Text("\(Image(systemName: "exclamationmark.triangle.fill")) \(problem)").foregroundStyle(.orange) } else { Text(detail).foregroundStyle(.secondary) }
                    }
                    .font(mono ? .scaled(11.5, design: .monospaced) : .caption).lineLimit(2).truncationMode(.middle)
                }
                if let note {
                    Text(note).font(.scaled(10.5, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).padding(.top, 1)
                }
            }
            Spacer(minLength: 8)
            control.environment(\.settingsInvalid, problem != nil)
        }
        .padding(.vertical, roomy ? 14 : 10).frame(minHeight: 46)
        .overlay(alignment: .top) { if first == false { SettingsDivider() } }
    }
}

extension EnvironmentValues {
    /// Whether the row the control sits in says its value is not valid.
    @Entry var settingsInvalid = false
}

/// The line between two rows of a card: a whole point tall and quiet, where the system's Divider is a grey hairline that stands out on the dark themes.
struct SettingsDivider: View {
    var body: some View { Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1).accessibilityHidden(true) }
}

/// A text field of a settings form, drawn as the capsule buttons are (the same quiet fill) with the theme's accent as its ring
/// while it has the focus. Put it on a `TextField`; a click anywhere in the box, padding included, puts the cursor in it.
private struct SettingsFieldModifier: ViewModifier {
    let width: CGFloat?
    let icon: String?
    @Environment(\.settingsInvalid) private var invalid
    /// The caller's own focus state, when it needs to know about the focus (to save as the person leaves the field); else the field keeps its own.
    let external: FocusState<Bool>.Binding?
    @FocusState private var own: Bool

    private var focus: FocusState<Bool>.Binding { external ?? $own }
    private var focused: Bool { focus.wrappedValue }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        HStack(spacing: 7) {
            if let icon { Image(systemName: icon).font(.scaled(12, weight: .medium)).foregroundStyle(.secondary).accessibilityHidden(true) }
            content.textFieldStyle(.plain).focused(focus).focusEffectDisabled()
            if invalid { Image(systemName: "exclamationmark.triangle.fill").font(.scaled(11)).foregroundStyle(.orange).accessibilityHidden(true) }
        }
            .padding(.horizontal, 10).padding(.vertical, 6)
            // a fixed width, or the whole width it is given
            .frame(minWidth: width, maxWidth: width ?? .infinity)
            // a fill only while idle: a half-point hairline over a translucent fill drew uneven edges
            .background(shape.fill(Color.primary.opacity(focused ? 0.09 : 0.07)))
            .overlay { if invalid { shape.strokeBorder(Color.orange, lineWidth: 1.5) } else if focused { shape.strokeBorder(Color.themeAccent, lineWidth: 1.5) } }
            .contentShape(shape)
            .onTapGesture { focus.wrappedValue = true }
            .animation(.easeOut(duration: 0.12), value: focused)
    }
}

extension View {
    /// `icon` is an SF Symbol drawn inside the box before the text (a magnifying glass for a search).
    /// Inside a row with a `problem` the ring is orange and a warning mark sits in the box, the same size as without them: nothing moves.
    func settingsField(width: CGFloat? = nil, icon: String? = nil, focused: FocusState<Bool>.Binding? = nil) -> some View {
        modifier(SettingsFieldModifier(width: width, icon: icon, external: focused))
    }
}

/// A filter as a small capsule that is on or off: a quiet fill when off, the theme's accent when on. A row of them narrows a list; the first of
/// a set that excludes each other is "All".
struct FilterChip: View {
    let title: String
    var icon: String?
    let on: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(.scaled(10, weight: .semibold)) }
                Text(title).font(.scaled(12, weight: .medium))
            }
            .foregroundStyle(on ? Color.themeAccent : hovered ? Color.primary : Color.secondary)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(on ? Color.themeAccent.opacity(0.18) : Color.primary.opacity(hovered ? 0.12 : 0.07)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain).onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A row whose control is wide (a text of several lines): the title and the detail on top and the control under them, the whole width of the card.
struct SettingsStackedRow<Control: View>: View {
    let title: String
    let detail: String
    var first = false
    @ViewBuilder var control: Control

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).fontWeight(.medium)
                if detail.isEmpty == false { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            control
        }
        .padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { if first == false { SettingsDivider() } }
    }
}

/// The system's pop-up button, as the Mac draws it, for a choice among a few words. SwiftUI's menu picker takes the theme's accent for its
/// fill and its text, which reads as a main action; this one is neutral and fills the width it is given.
struct NativePopUp: NSViewRepresentable {
    let items: [String]
    @Binding var selection: Int

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.target = context.coordinator
        button.action = #selector(Coordinator.changed(_:))
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        // a row switched off (`.disabled`) dims its pop-up too
        button.isEnabled = context.environment.isEnabled
        if button.itemTitles != items {
            button.removeAllItems()
            button.addItems(withTitles: items)
        }
        if button.indexOfSelectedItem != selection, items.indices.contains(selection) { button.selectItem(at: selection) }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? nsView.intrinsicContentSize.width, height: nsView.intrinsicContentSize.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: NativePopUp
        init(_ parent: NativePopUp) { self.parent = parent }
        @objc func changed(_ sender: NSPopUpButton) { parent.selection = sender.indexOfSelectedItem }
    }
}

/// A copy button after whatever it modifies, which fades in while the pointer is over the pair and shows a check for a moment once it has
/// copied. The room is kept while it is hidden, so the text does not move when it appears.
private struct CopyOnHover: ViewModifier {
    let text: String
    @State private var hovered = false
    @State private var copied = false

    func body(content: Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            content
            Button(action: copy) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.scaled(10.5, weight: .medium))
                    .foregroundStyle(copied ? Color.green : Color.secondary).frame(width: 20, height: 20)
                    .background(Circle().fill(Color.primary.opacity(0.1))).contentShape(Circle())
            }
            .buttonStyle(.plain).help("Copy").accessibilityLabel("Copy")
            .opacity(hovered || copied ? 1 : 0).allowsHitTesting(hovered || copied)
            .animation(.easeOut(duration: 0.15), value: hovered)
        }
        .onHover { hovered = $0 }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            copied = false
        }
    }
}

extension View {
    /// A copy button for `text` after this view, shown while the pointer is over it: for a path, a URL or an error a person may want to paste.
    func copyOnHover(_ text: String) -> some View { modifier(CopyOnHover(text: text)) }
}

struct SettingsTabCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .padding(.horizontal, 14)
            .settingsCard()
    }
}

extension View {
    /// The card every group of rows, list and note of Settings sits on: rounded 14, `secondary` at 7 %.
    func settingsCard() -> some View { background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.07))) }

    /// The small uppercase title over a group or a list: the type and the colour; the caller adds the padding its place needs.
    func sectionLabel() -> some View { font(.caption2).fontWeight(.semibold).foregroundStyle(.secondary).textCase(.uppercase) }
}

/// A state as a 16 pt round mark with a white symbol: `checkmark` green for ready, `exclamationmark` yellow for a warning, `xmark` orange for a
/// failure. Next to a spinner (`ProgressView().controlSize(.mini)` in the same 16 pt) for what is still being looked at.
struct StatusMark: View {
    let symbol: String
    let color: Color
    let label: String

    var body: some View {
        Image(systemName: symbol).font(.scaled(9, weight: .heavy)).foregroundStyle(.white)
            .frame(width: 16, height: 16).background(Circle().fill(color)).accessibilityLabel(label)
    }
}

/// The tile of an agent role: the mark of the provider it runs on in a rounded square, so which model is working is seen before it is read. `off`
/// (a role that is not in use) shows a quiet power symbol; a provider with no icon shows a question mark.
struct RoleTile: View {
    let provider: String?
    let icons: [String: String]
    var off = false

    var body: some View {
        Group {
            if off {
                Image(systemName: "power").font(.scaled(14, weight: .medium)).foregroundStyle(.tertiary)
            } else if let provider, let icon = icons[provider] {
                ProviderMark(name: icon, size: 17)
            } else {
                Image(systemName: "questionmark.circle").font(.scaled(15)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 34, height: 34).background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.07)))
        .accessibilityHidden(true)
    }
}

/// `Identity gh · Account pro · Model sonnet · Effort high`: a label quiet and its value in the text colour; what is not set is left out.
func roleSummary(_ fields: RoleFields) -> Text {
    let parts: [(String, String?)] = [("Identity", fields.profile), ("Account", fields.provider), ("Model", fields.model), ("Effort", fields.effort)]
    let set = parts.compactMap { label, value in value.flatMap { $0.isEmpty ? nil : (label, $0) } }
    guard set.isEmpty == false else { return Text("Not set").foregroundStyle(.secondary) }
    return set.enumerated().reduce(Text("")) { text, item in
        let (index, part) = item
        return text + Text(index == 0 ? "" : "  \u{00b7}  ").foregroundStyle(.tertiary) + Text("\(part.0) ").foregroundStyle(.secondary) + Text(part.1).foregroundStyle(.primary)
    }
}

/// A group of a tab: a small uppercase title over a card of rows.
struct SettingsGroup<Content: View, Accessory: View>: View {
    let title: String
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).sectionLabel()
                Spacer(minLength: 8)
                accessory
            }
            .padding(.leading, 14).padding(.top, 8)
            SettingsTabCard { content }
        }
    }
}

extension SettingsGroup where Accessory == EmptyView {
    init(title: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, accessory: { EmptyView() }, content: content)
    }
}

/// A line a page puts at the right of its own header, only when there is something to say (the Behavior page's "Saved", or why it cannot save).
struct SettingsHeaderNote: Equatable {
    /// `plain`: a fact that is no one's fault, said quietly
    enum Tone { case saved, problem, plain }
    let text: String
    let tone: Tone
    /// A problem is said to VoiceOver when it appears; one whose page says it itself (once, when the answer comes) leaves it to the page.
    var announces = true
    /// The engine did not apply the save: the note has a way to ask it again, without a new edit.
    var asksAgain = false
}

struct SettingsHeaderNoteKey: PreferenceKey {
    static let defaultValue: SettingsHeaderNote? = nil
    static func reduce(value: inout SettingsHeaderNote?, nextValue: () -> SettingsHeaderNote?) { value = nextValue() ?? value }
}

/// The top of a page: an icon, the title and a line, and the page's note at the right when it has one, or below the title when the page is
/// too narrow for both.
struct SettingsPageHeader: View {
    let page: SettingsPage
    var note: SettingsHeaderNote?

    private var tile: some View {
        Image(systemName: page.icon)
            .font(.scaled(16, weight: .medium)).foregroundStyle(Color.themeAccent)
            .frame(width: 38, height: 38)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.themeAccent.opacity(0.16)))
            .accessibilityHidden(true)
    }

    // the two lines are about as tall as the tile (a Spacer here would take the whole height the page's bar offers)
    private var titles: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(page.rawValue).font(.title3.weight(.semibold))
            Text(page.detail).font(.callout).foregroundStyle(.secondary)
        }
    }

    // an engine's message can be long: it wraps instead of being cut
    @ViewBuilder private func noteView(_ note: SettingsHeaderNote) -> some View {
        HStack(spacing: 10) {
            Group {
                switch note.tone {
                case .saved: Label(note.text, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .problem: Label(note.text, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                case .plain: Label(note.text, systemImage: "info.circle").foregroundStyle(.secondary)
                }
            }
            .font(.callout).fixedSize(horizontal: false, vertical: true)
            if note.asksAgain { AskAgainButton() }
        }
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                tile
                titles.fixedSize(horizontal: true, vertical: false)
                if let note {
                    Spacer(minLength: 16)
                    noteView(note).multilineTextAlignment(.trailing).frame(maxWidth: 420, alignment: .trailing)
                }
            }
            // too narrow for the title and the note side by side: the note goes under the title, with the room of the page
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 12) { tile; titles }
                if let note { noteView(note).frame(maxWidth: .infinity, alignment: .leading) }
            }
        }
        // a problem appears while the person looks elsewhere: say it to VoiceOver too
        .onChange(of: note) { _, note in
            if let note, note.tone == .saved || (note.tone == .problem && note.announces) { AccessibilityNotification.Announcement(note.text).post() }
        }
        // room for the close button, which sits over the corner of the header
        .padding(.trailing, 32)
    }
}

/// A line of a page that says what went wrong in its words, in orange, and says it to VoiceOver when it appears or changes (`announces`).
struct ProblemLine: View {
    let text: String
    var font: Font = .callout
    var announces = true

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill").font(font).foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
            .onAppear { if announces { AccessibilityNotification.Announcement(text).post() } }
            .onChange(of: text) { _, text in if announces { AccessibilityNotification.Announcement(text).post() } }
    }
}

/// What the engine answered to the last save when it did not apply it (`ReloadStatus`): the same on every page, until a save is applied or
/// Carrier stops. A problem is said to VoiceOver once, when the answer comes (not each time the person comes back to the page), and has a
/// way out: Ask Carrier again asks the engine without a save.
struct ReloadNote: View {
    private let engine = ReloadStatus.shared

    var body: some View {
        Group {
            if let words = engine.words {
            HStack(spacing: 10) {
                if engine.isProblem {
                    ProblemLine(text: words, announces: false)
                    AskAgainButton()
                } else {
                    Label(words, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            }
        }
        .announcesReloadProblems()
    }
}

/// Asks the engine again without a save, for a refusal that may be gone (the file was fixed by hand).
struct AskAgainButton: View {
    private let engine = ReloadStatus.shared

    var body: some View {
        Button { engine.ask() } label: { Label("Ask Carrier again", systemImage: "arrow.clockwise") }
            .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small).disabled(engine.pending)
    }
}

extension View {
    /// Says a problem answer of the engine to VoiceOver when it comes, on the page that is open (a page that shows `ReloadNote` or the header).
    func announcesReloadProblems() -> some View {
        onChange(of: ReloadStatus.shared.answers) {
            if let outcome = ReloadStatus.shared.outcome, outcome.isProblem, let words = reloadWords(outcome) { AccessibilityNotification.Announcement(words).post() }
        }
    }
}

/// `NativePopUp` over a value: the choices as (value, title) pairs, the one chosen bound as the value itself. A stored value that is not on the
/// list shows the first choice, as the pages already read an unknown value as their default.
struct ChoicePopUp<Value: Hashable>: View {
    let label: String
    let options: [(value: Value, title: String)]
    @Binding var selection: Value
    var width: CGFloat = 160

    var body: some View {
        NativePopUp(
            items: options.map(\.title),
            selection: Binding(
                get: { options.firstIndex { $0.value == selection } ?? 0 },
                set: { selection = options[$0].value }
            )
        )
        .accessibilityLabel(label).frame(width: width)
    }
}

/// What goes under a page's header: the groups and a Reset row where the page has many controls.
struct SettingsPageBody<Content: View>: View {
    var reset: (() -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
            if let reset {
                SettingsTabCard {
                    SettingsTabRow(title: "Reset", detail: "Puts this page back to how it came", first: true) {
                        Button(action: reset) { Label("Reset", systemImage: "arrow.counterclockwise") }.buttonStyle(SecondaryCapsuleButtonStyle())
                    }
                }
            }
        }
    }
}

/// A sample of what the rows around it change, inside the group of those rows so that it sits next to the controls.
struct SettingsPreview<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview").sectionLabel()
            content.frame(maxWidth: .infinity)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { SettingsDivider() }
    }
}

struct GeneralTabView: View {
    /// Three times as the two settings write them now, taken as if it were 6:00 PM: 11 minutes ago, this afternoon and this morning, so a
    /// clock shows both its PM and its AM.
    private func displayPreview() -> some View {
        let calendar = Calendar.current
        func today(_ hour: Int, _ minute: Int) -> Date { calendar.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date() }
        let now = today(18, 0)
        let format = TimeFormat.stored()
        return SettingsPreview {
            HStack(spacing: 10) {
                ForEach([today(17, 49), today(15, 40), today(9, 5)], id: \.self) { date in
                    Text(timeText(date, now: now, format: format)).monospacedDigit()
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.1)))
                }
            }
        }
    }

    @AppStorage(AppPreferences.styleKey) private var style = AppPreferences.defaultStyle.rawValue
    @AppStorage(AppPreferences.animatesKey) private var animates = AppPreferences.defaultAnimates
    @AppStorage(showEpicsKey) private var showsEpics = AppPreferences.defaultShowsEpics
    @AppStorage(AppPreferences.timeStyleKey) private var timeStyle = TimeStyle.relative.rawValue
    @AppStorage(AppPreferences.clockHoursKey) private var clockHours = ClockHours.system.rawValue

    var body: some View {
        SettingsPageBody(reset: { AppPreferences().reset(.general) }) {
            SettingsGroup(title: "Menu bar") {
                SettingsTabRow(title: "Icon style", detail: "What the icon in the menu bar shows", first: true) {
                    // a saved value that is not a style reads as the default, as the icon does
                    ChoicePopUp(
                        label: "Icon style", options: IconStyle.allCases.map { (value: $0, title: $0.title) },
                        selection: Binding(get: { IconStyle(rawValue: style) ?? AppPreferences.defaultStyle }, set: { style = $0.rawValue })
                    )
                }
                SettingsTabRow(title: "Animate the icon", detail: "A segment moves over the bar while epics run") {
                    Toggle("Animate the icon", isOn: $animates).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(title: "List epics in the menu", detail: "The epics that run or wait show under the status") {
                    Toggle("List epics in the menu", isOn: $showsEpics).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsGroup(title: "Display") {
                SettingsTabRow(title: "Time format", detail: "Ages read \"11m\", or as the time of the event, \"14:32\"", first: true) {
                    // a saved value that is not a choice reads as the default, as the formatter does
                    ChoicePopUp(
                        label: "Time format", options: [(value: TimeStyle.relative, title: "Relative"), (value: .clock, title: "Clock")],
                        selection: Binding(get: { TimeStyle(rawValue: timeStyle) ?? .relative }, set: { timeStyle = $0.rawValue })
                    )
                }
                SettingsTabRow(title: "Clock", detail: "How clock times count the hours") {
                    ChoicePopUp(
                        label: "Clock", options: [(value: ClockHours.system, title: "System"), (value: .h12, title: "12 hours"), (value: .h24, title: "24 hours")],
                        selection: Binding(get: { ClockHours(rawValue: clockHours) ?? .system }, set: { clockHours = $0.rawValue })
                    )
                }
                displayPreview()
            }
        }
    }
}

/// How the app looks: the color scheme of every window, the theme, the text size of the whole interface, how tight the rows are, and the
/// font of code and output with a sample that follows each choice.
struct AppearanceTabView: View {
    @AppStorage(AppPreferences.colorSchemeKey) private var colorScheme = AppPreferences.defaultColorScheme
    @AppStorage(AppPreferences.themeKey) private var theme = AppPreferences.defaultTheme
    @AppStorage(AppPreferences.accentKey) private var accent: AccentColor?
    @AppStorage(AppPreferences.tintKey) private var tint = AppPreferences.defaultTint
    @AppStorage(AppPreferences.translucentKey) private var translucentChoice: Bool?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme
    @AppStorage(TypeScale.percentKey) private var textSize = 100
    @AppStorage(AppPreferences.densityKey) private var density = AppPreferences.defaultDensity
    @AppStorage(AppPreferences.monospaceFamilyKey) private var family = MonospaceSettings.systemFamily
    @AppStorage(AppPreferences.monospaceSizeKey) private var codeSize = Double(MonospaceSettings.defaultSize)
    @AppStorage(AppPreferences.monospaceLineHeightKey) private var lineHeight = LineHeight.normal
    @AppStorage(AppPreferences.monospaceLigaturesKey) private var ligatures = true
    @AppStorage(AppPreferences.monospaceWrapKey) private var wrapLongLines = true
    @AppStorage(AppPreferences.monospaceLineNumbersKey) private var lineNumbers = false

    /// A few lines of code under the settings: a long line to wrap, and the pairs of characters a ligature joins.
    private static let sample = """
        func total(_ lines: [Int]) -> Int {
            // a line that is longer than the room it has, so wrapping and scrolling sideways show: 0123456789 abcdefghij 0123456789
            lines.filter { $0 != 0 && $0 >= 1 }.reduce(0, +)
        }
        """

    private func codePreview() -> some View {
        SettingsPreview { CodeBlockView(language: "swift", code: Self.sample) }
    }

    @AppStorage(AppPreferences.statesByShapeKey) private var statesByShape = false
    @AppStorage(AppPreferences.messageWidthKey) private var messageWidth = AppPreferences.defaultMessageWidth
    @State private var previewRoom: CGFloat = 0

    /// A message of the agent in a column that is to the room as the chosen width is to the widest one, drawn as a bubble on a track that is
    /// the widest, so the four differ in where the lines break and in how much of the track the bubble takes.
    private var messagePreview: some View {
        SettingsPreview {
            VStack(alignment: .leading, spacing: 0) {
                MarkdownView(text: "I opened a pull request for the settings epic and asked the reviewer for a second look. The width of a message is how far a line runs before it wraps: a narrow column is easy on the eye, and a wide one fits more of a table or a long command, like `pnpm test && pnpm typecheck`.")
                    .padding(12)
                    .frame(width: previewRoom * messageWidth.points / MessageWidth.ultraWide.points, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.themeAccent.opacity(0.14)))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { previewRoom = $0 }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        }
    }

    /// The four states as the app draws them now, with or without their symbols, larger than they are in a row so the mark inside reads.
    private var statesPreview: some View {
        SettingsPreview {
            // together in the middle, not one to a quarter of the width
            HStack(alignment: .top, spacing: 0) {
                state("Working") { StateGlyph(state: .running) }
                state("Needs attention") { StateGlyph(state: .needsYou, attention: .input) }
                state("Ready for test") { StateGlyph(state: .ready) }
                state("A problem") { StateGlyph(state: .needsYou, attention: .error) }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func state(_ title: String, @ViewBuilder glyph: () -> some View) -> some View {
        VStack(spacing: 8) {
            // at its own size: scaling the 20-point glyph up scaled its pixels, and the ring (a layer) showed them
            glyph().frame(width: 28, height: 28)
            Text(title).font(.scaled(12)).foregroundStyle(.secondary)
        }
        .frame(width: 120)
    }

    var body: some View {
        SettingsPageBody(reset: { AppPreferences().reset(.appearance) }) {
            SettingsGroup(title: "Theme") {
                ThemeGallery(theme: $theme)
            }
            SettingsGroup(title: "Look") {
                SettingsTabRow(title: "Color scheme", detail: "System follows the Mac; light and dark stay as chosen", first: true) {
                    ChoicePopUp(label: "Color scheme", options: ColorSchemeChoice.allCases.map { (value: $0, title: $0.title) }, selection: $colorScheme)
                }
                SettingsTabRow(title: "Text size", detail: "The size of the text of the whole app, \(textSize)%") {
                    Slider(
                        value: Binding(get: { Double(textSize) }, set: { textSize = Int($0) }),
                        in: Double(TypeScale.range.lowerBound)...Double(TypeScale.range.upperBound), step: 5
                    )
                    .frame(width: 160).accessibilityLabel("Text size").accessibilityValue("\(textSize) percent")
                }
                SettingsTabRow(title: "Density", detail: "The space in the sidebar rows and between the messages") {
                    ChoicePopUp(label: "Density", options: Density.allCases.map { (value: $0, title: $0.title) }, selection: $density)
                }
                SettingsTabRow(title: "Message width", detail: "How wide a message gets before it wraps") {
                    ChoicePopUp(
                        label: "Message width", options: MessageWidth.allCases.map { (value: $0, title: "\($0.title) · \(Int($0.points)) pt") },
                        selection: $messageWidth, width: 180
                    )
                }
                messagePreview
                SettingsTabRow(title: "Tell states apart by shape", detail: "A symbol in each state, so that color is not the only clue") {
                    Toggle("Tell states apart by shape", isOn: $statesByShape).labelsHidden().toggleStyle(.switch)
                }
                statesPreview
            }
            SettingsGroup(title: "Code and output") {
                SettingsTabRow(title: "Font", detail: "The monospaced fonts installed on this Mac", first: true) {
                    // a family that is no longer installed shows as the system's, as the views draw it
                    ChoicePopUp(
                        label: "Font", options: ([MonospaceSettings.systemFamily] + MonospaceStyle.installedFamilies).map { (value: $0, title: $0) },
                        selection: Binding(
                            get: { MonospaceStyle.installedFamilies.contains(family) ? family : MonospaceSettings.systemFamily },
                            set: { family = $0 }
                        ),
                        width: 200
                    )
                }
                SettingsTabRow(title: "Size", detail: "\(Int(codeSize)) pt, before the text size of the whole app") {
                    Slider(value: $codeSize, in: Double(MonospaceSettings.sizeRange.lowerBound)...Double(MonospaceSettings.sizeRange.upperBound), step: 1)
                        .frame(width: 160).accessibilityLabel("Code size").accessibilityValue("\(Int(codeSize)) points")
                }
                SettingsTabRow(title: "Line height", detail: "The room between the lines of code and output") {
                    ChoicePopUp(label: "Line height", options: LineHeight.allCases.map { (value: $0, title: $0.title) }, selection: $lineHeight)
                }
                SettingsTabRow(title: "Ligatures", detail: "Joins pairs such as != and >= where the font has them") {
                    Toggle("Ligatures", isOn: $ligatures).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(title: "Wrap long lines", detail: "Off keeps each line whole and scrolls sideways") {
                    Toggle("Wrap long lines", isOn: $wrapLongLines).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(title: "Line numbers", detail: "In code blocks and the output of a command") {
                    Toggle("Line numbers", isOn: $lineNumbers).labelsHidden().toggleStyle(.switch)
                }
                codePreview()
            }
            SettingsGroup(title: "Color") {
                SettingsTabRow(title: "Accent color", detail: "Buttons, switches and the selection; the first one is the theme's own", first: true) {
                    AccentSwatches(theme: theme, scheme: scheme == .dark ? .dark : .light, accent: $accent)
                }
                SettingsTabRow(title: "Tint the windows", detail: "A touch of the accent on the backgrounds") {
                    ChoicePopUp(label: "Tint the windows", options: Tint.allCases.map { (value: $0, title: $0.title) }, selection: $tint)
                }
                SettingsTabRow(title: "Translucent windows", detail: "Off draws solid backgrounds; it follows the Mac's Reduce transparency until you choose") {
                    Toggle("Translucent windows", isOn: Binding(
                        get: { translucentChoice ?? (reduceTransparency == false) }, set: { translucentChoice = $0 }
                    ))
                    .labelsHidden().toggleStyle(.switch)
                }
            }
        }
    }
}

/// The nine themes in a grid of three, each as its light and its dark version side by side; the chosen one has the accent's edge.
private struct ThemeGallery: View {
    @Binding var theme: Theme

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(Theme.allCases, id: \.self) { option in
                Button { theme = option } label: {
                    VStack(spacing: 8) {
                        HStack(spacing: 6) {
                            ThemePreview(theme: option, scheme: .light)
                            ThemePreview(theme: option, scheme: .dark)
                        }
                        Text(option.title).font(.callout)
                    }
                    .padding(8).frame(maxWidth: .infinity)
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(option == theme ? Color.themeAccent : Color.secondary.opacity(0.2), lineWidth: option == theme ? 2 : 1))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title).accessibilityAddTraits(option == theme ? .isSelected : [])
            }
        }
        .padding(.vertical, 12)
    }
}

/// A made-up window in one version of a theme: a sidebar with a selected row, a title, two messages and a button in the accent. Only
/// what the theme paints (the window, the sidebar, the accent); the grey of the text is a stand-in.
private struct ThemePreview: View {
    let theme: Theme
    let scheme: ThemeScheme

    var body: some View {
        let surfaces = themeSurfaces(theme, scheme: scheme, translucent: false)
        let accent = surfaces.accent.map(Color.init) ?? .accentColor
        let ink = scheme == .dark ? Color.white : Color.black
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Capsule().fill(ink.opacity(0.25)).frame(width: 14, height: 3)
                RoundedRectangle(cornerRadius: 2).fill(accent.opacity(0.35)).frame(height: 8)
                Capsule().fill(ink.opacity(0.2)).frame(width: 18, height: 3)
                Capsule().fill(ink.opacity(0.2)).frame(width: 14, height: 3)
                Spacer(minLength: 0)
            }
            .padding(6).frame(width: 34).background(Color(surfaces.sidebar))
            VStack(alignment: .leading, spacing: 6) {
                Capsule().fill(ink.opacity(0.4)).frame(width: 28, height: 4)
                VStack(alignment: .leading, spacing: 3) {
                    Capsule().fill(ink.opacity(0.22)).frame(height: 3)
                    Capsule().fill(ink.opacity(0.22)).frame(width: 34, height: 3)
                }
                .padding(5).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 4).fill(ink.opacity(0.07)))
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Capsule().fill(ink.opacity(0.12)).frame(height: 8)
                    Capsule().fill(accent).frame(width: 14, height: 8)
                }
            }
            .padding(6).frame(maxWidth: .infinity).background(Color(surfaces.window))
        }
        .frame(height: 84).clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.3), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

/// The theme's own accent and the seven colors, as discs; the chosen one has a ring.
private struct AccentSwatches: View {
    let theme: Theme
    let scheme: ThemeScheme
    @Binding var accent: AccentColor?

    var body: some View {
        HStack(spacing: 8) {
            swatch("\(theme.title) accent", color: themeSurfaces(theme, scheme: scheme, translucent: false).accent.map(Color.init) ?? .accentColor, chosen: accent == nil) { accent = nil }
            ForEach(AccentColor.allCases, id: \.self) { option in
                swatch(option.title, color: Color(option.color), chosen: accent == option) { accent = option }
            }
        }
    }

    private func swatch(_ name: String, color: Color, chosen: Bool, choose: @escaping () -> Void) -> some View {
        Button(action: choose) {
            Circle().fill(color).frame(width: 18, height: 18)
                .padding(3).overlay(Circle().strokeBorder(chosen ? Color.primary.opacity(0.7) : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain).help(name).accessibilityLabel(name).accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// The sidebar's grouping and sorts, which its own menus change too (one preference, two controls), and what each session row shows.
struct SidebarTabView: View {
    @AppStorage(SidebarStore.groupByKey) private var groupBy = GroupBy.status
    @AppStorage(SidebarStore.sessionSortKey) private var sessionSort = SessionSort.workspace
    @AppStorage(SidebarStore.archiveSortKey) private var archiveSort = ArchiveSort.dateArchived
    @AppStorage(SidebarStore.showsIconKey) private var showsIcon = true
    @AppStorage(SidebarStore.showsBranchKey) private var showsBranch = true
    @AppStorage(SidebarStore.showsProvidersKey) private var showsProviders = true
    @AppStorage(SidebarStore.showsAgeKey) private var showsAge = true

    /// A session of the preview: it has a branch, two providers and an age, so each switch has something to hide.
    private static let sample = SessionRow(
        id: "preview", title: "Fix the flaky login test", workspace: "carrier", agent: "claude", state: .idle,
        updatedAt: Date(timeIntervalSinceNow: -11 * 60), branch: "fix/login-flake", folder: "/preview", providers: ["claude", "codex"]
    )

    var body: some View {
        SettingsPageBody(reset: { AppPreferences().reset(.sidebar) }) {
            SettingsGroup(title: "Order") {
                SettingsTabRow(title: "Group epics by", detail: "How the epics under Carrier are grouped", first: true) {
                    picker("Group epics by", selection: $groupBy, options: GroupBy.allCases) { $0.title }
                }
                SettingsTabRow(title: "Sort sessions", detail: "How the Sessions list is grouped and ordered") {
                    picker("Sort sessions", selection: $sessionSort, options: SessionSort.allCases) { $0.title }
                }
                SettingsTabRow(title: "Sort the Archive", detail: "How the archived sessions are ordered") {
                    picker("Sort the Archive", selection: $archiveSort, options: ArchiveSort.allCases) { $0.title }
                }
            }
            SettingsGroup(title: "Session rows") {
                SettingsTabRow(title: "Project icon", detail: "The colored square with the project's initials", first: true) {
                    Toggle("Project icon", isOn: $showsIcon).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(title: "Branch", detail: "Where the session works, the branch or the base folder") {
                    Toggle("Branch", isOn: $showsBranch).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(title: "Providers", detail: "The marks of the providers the session used") {
                    Toggle("Providers", isOn: $showsProviders).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(title: "Age", detail: "How long ago the session was last active") {
                    Toggle("Age", isOn: $showsAge).labelsHidden().toggleStyle(.switch)
                }
                SettingsPreview {
                    SessionRowView(row: Self.sample, showsWorkspace: true).allowsHitTesting(false)
                }
            }
        }
    }

    private func picker<Value: Hashable>(_ name: String, selection: Binding<Value>, options: [Value], title: @escaping (Value) -> String) -> some View {
        ChoicePopUp(label: name, options: options.map { (value: $0, title: title($0)) }, selection: selection)
    }
}

/// How the message box behaves (the key that sends and what the system does to the text) and what the conversation does and shows.
struct ChatTabView: View {
    @AppStorage(AppPreferences.sendKeyKey) private var sendKey = AppPreferences.defaultSendKey
    @AppStorage(AppPreferences.whileWorkingKey) private var whileWorking = AppPreferences.defaultWhileWorking
    @AppStorage(AppPreferences.writingToolsKey) private var writingTools = AppPreferences.defaultWritingTools
    @AppStorage(AppPreferences.checksSpellingKey) private var checksSpelling = AppPreferences.defaultChecksSpelling
    @AppStorage(AppPreferences.correctsSpellingKey) private var correctsSpelling = AppPreferences.defaultCorrectsSpelling
    @AppStorage(AppPreferences.followsOutputKey) private var followsOutput = AppPreferences.defaultFollowsOutput
    @AppStorage(AppPreferences.messageTimesKey) private var messageTimes = AppPreferences.defaultMessageTimes
    @AppStorage(AppPreferences.toolOutputKey) private var toolOutput = AppPreferences.defaultToolOutput
    @AppStorage(AppPreferences.opensFailedCallsKey) private var opensFailedCalls = AppPreferences.defaultOpensFailedCalls
    @AppStorage(AppPreferences.diffStyleKey) private var diffStyle = AppPreferences.defaultDiffStyle
    @AppStorage(AppPreferences.outputLengthKey) private var outputLength = AppPreferences.defaultOutputLength
    @AppStorage(AppPreferences.showsReasoningKey) private var showsReasoning = AppPreferences.defaultShowsReasoning

    var body: some View {
        SettingsPageBody(reset: { AppPreferences().reset(.chat) }) {
            SettingsGroup(title: "Message box") {
                SettingsTabRow(title: "Send with", detail: "The other key makes a new line", first: true) {
                    ChoicePopUp(label: "Send with", options: [(value: SendKey.return, title: "Return"), (value: .commandReturn, title: "\u{2318}Return")], selection: $sendKey)
                }
                SettingsTabRow(title: "While the agent works", detail: "What sending does while it answers: hold the message until the turn ends, or stop the turn and send it") {
                    ChoicePopUp(label: "While the agent works", options: [(value: WhileWorking.queue, title: "Queue it"), (value: .interrupt, title: "Interrupt")], selection: $whileWorking)
                }
                SettingsTabRow(title: "Writing Tools", detail: "The system's offer to rewrite or proofread what you select") {
                    Toggle("Writing Tools", isOn: $writingTools).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(title: "Check spelling", detail: "Underline words that look misspelled") {
                    Toggle("Check spelling", isOn: $checksSpelling).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(title: "Correct spelling automatically", detail: "Fix a misspelled word as you type it") {
                    Toggle("Correct spelling automatically", isOn: $correctsSpelling).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsGroup(title: "Conversation") {
                SettingsTabRow(title: "Follow new output", detail: "Scroll to what arrives while you are at the end", first: true) {
                    Toggle("Follow new output", isOn: $followsOutput).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(title: "Message times", detail: "When a message shows the time it was written, as in General") {
                    ChoicePopUp(label: "Message times", options: MessageTimes.allCases.map { (value: $0, title: $0.title) }, selection: $messageTimes)
                }
                SettingsTabRow(title: "Tool output", detail: "What the agent's tools show: nothing, each run folded, or every call open") {
                    ChoicePopUp(label: "Tool output", options: ToolOutputMode.allCases.map { (value: $0, title: $0.title) }, selection: $toolOutput)
                }
                SettingsTabRow(title: "Open the calls that failed", detail: "A call that failed opens by itself, even when the rest are folded") {
                    Toggle("Open the calls that failed", isOn: $opensFailedCalls).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(title: "Diff style", detail: "How an edit reads: its lines one under the other, or removed and added side by side") {
                    ChoicePopUp(label: "Diff style", options: DiffStyle.allCases.map { (value: $0, title: $0.title) }, selection: $diffStyle)
                }
                SettingsTabRow(title: "Output length", detail: "How many lines of an output show before Show more") {
                    ChoicePopUp(label: "Output length", options: OutputLength.allCases.map { (value: $0, title: $0.title) }, selection: $outputLength)
                }
                SettingsTabRow(title: "Show reasoning", detail: "The agent's reasoning, folded under its message, when its host sends it") {
                    Toggle("Show reasoning", isOn: $showsReasoning).labelsHidden().toggleStyle(.switch)
                }
            }
        }
    }
}

struct NotificationsTabView: View {
    @AppStorage(notifyNeedsYouKey) private var needsYou = true
    @AppStorage(notifyReadyForTestKey) private var readyForTest = true
    @AppStorage(notifyProblemKey) private var problem = false
    @AppStorage(notifyChatNeedsAttentionKey) private var chatNeedsAttention = true
    @AppStorage(notifyChatDoneKey) private var chatDone = false
    @AppStorage(notifyOnlyWhenAwayKey) private var onlyWhenAway = true
    @AppStorage(notifyDockBadgeKey) private var dockBadge = true
    @AppStorage(notifySoundKey) private var sound = true
    @AppStorage(notifyReminderKey) private var reminder = ReminderInterval.never.rawValue
    @AppStorage(notifyQuietKey) private var quiet = false
    @AppStorage(notifyQuietStartKey) private var quietStart = QuietHours.defaultStart
    @AppStorage(notifyQuietEndKey) private var quietEnd = QuietHours.defaultEnd
    @State private var permission: NotificationPermission?
    @State private var testAdvice: String?

    var body: some View {
        SettingsPageBody(reset: { AppPreferences().reset(.notifications) }) {
            SettingsGroup(title: "Carrier") {
                SettingsTabRow(title: "Needs attention", detail: "An epic stopped and waits for a person", first: true) {
                    Toggle("Needs attention", isOn: $needsYou).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(title: "Ready for test", detail: "An epic finished and has a PR to try") {
                    Toggle("Ready for test", isOn: $readyForTest).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(title: "A problem", detail: "GitHub refuses a repo, or Carrier stops by itself") {
                    Toggle("A problem", isOn: $problem).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsGroup(title: "Chat") {
                SettingsTabRow(title: "Needs attention", detail: "A session waits for an approval", first: true) {
                    Toggle("Chat needs attention", isOn: $chatNeedsAttention).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(title: "Done", detail: "A session finished its turn") {
                    Toggle("Chat done", isOn: $chatDone).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsGroup(title: "When") {
                SettingsTabRow(title: "Only when Carrier is not in front", detail: "No banner while its window is the one you are looking at", first: true) {
                    Toggle("Only when Carrier is not in front", isOn: $onlyWhenAway).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsGroup(title: "Dock") {
                SettingsTabRow(title: "Dock badge", detail: "The Dock icon counts the epics that need a person and the sessions that wait for an approval", first: true) {
                    Toggle("Dock badge", isOn: $dockBadge).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsGroup(title: "Sound") {
                SettingsTabRow(title: "Play a sound", detail: "A banner plays the notification sound", first: true) {
                    Toggle("Play a sound", isOn: $sound).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsGroup(title: "Reminders") {
                SettingsTabRow(title: "Remind me again", detail: "While an epic or a session still needs attention. Ready for test and Done never remind", first: true) {
                    // a saved value that is not a choice reads as Never, as the watcher does
                    ChoicePopUp(
                        label: "Remind me again", options: ReminderInterval.allCases.map { (value: $0, title: $0.title) },
                        selection: Binding(get: { ReminderInterval(rawValue: reminder) ?? .never }, set: { reminder = $0.rawValue })
                    )
                }
            }
            SettingsGroup(title: "Quiet hours") {
                SettingsTabRow(title: "Quiet hours", detail: "No banner and no sound: notifications wait in the Notification Center", first: true) {
                    Toggle("Quiet hours", isOn: $quiet).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(title: "From", detail: "When the quiet starts") {
                    timePicker("From", $quietStart)
                }
                .disabled(quiet == false)
                SettingsTabRow(title: "Until", detail: "When it ends, the next day if it is earlier than the start") {
                    timePicker("Until", $quietEnd)
                }
                .disabled(quiet == false)
            }
            SettingsGroup(title: "Permission") {
                SettingsTabRow(title: "System permission", detail: permission?.text ?? "Checking…", first: true) {
                    HStack {
                        if permission != .noBundle {
                            Button { NSWorkspace.shared.open(Self.systemSettingsURL) } label: { Label("Open System Settings", systemImage: "gearshape") }
                        }
                        if permission == .notAsked {
                            Button { send() } label: { Label("Allow", systemImage: "checkmark") }.buttonStyle(PrimaryCapsuleButtonStyle())
                        }
                        Button { send() } label: { Label("Send a test", systemImage: "paperplane") }.disabled(permission == .noBundle)
                    }
                }
            }
            if let testAdvice {
                Label(testAdvice, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange).padding(.horizontal, 14)
            }
        }
        .buttonStyle(SecondaryCapsuleButtonStyle())
        .task { refresh() }
        // back from System Settings, where the person may have changed the answer
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    /// A time of day kept as minutes after midnight, chosen from a menu of every half hour (and the saved time itself when it is none of
    /// those), written in the clock the Time format setting says.
    private func timePicker(_ name: String, _ minutes: Binding<Int>) -> some View {
        let hours = TimeFormat.stored().hours
        let options = Array(Set(Array(stride(from: 0, to: 1440, by: 30)) + [minutes.wrappedValue])).sorted()
        func label(_ minutes: Int) -> String {
            let date = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
            return clockTime(date, hours: hours, locale: .current)
        }
        return ChoicePopUp(label: name, options: options.map { (value: $0, title: label($0)) }, selection: minutes)
    }

    private static let systemSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!

    /// A test that macOS would swallow says why instead; otherwise it is sent (the first one also asks for the permission).
    private func send() {
        testAdvice = permission?.testAdvice
        guard testAdvice == nil else { return }
        SystemNotificationCentre.shared.sendTest()
    }

    private func refresh() {
        readPermission(bundleIdentifier: Bundle.main.bundleIdentifier, reader: SystemNotificationCentre.shared) {
            permission = $0
            if $0.testAdvice == nil { testAdvice = nil }
        }
    }
}
