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
    /// A third line for what the row is and not what it says (a path, a login): monospaced and quieter than the detail.
    var note: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).fontWeight(.medium)
                if detail.isEmpty == false {
                    Text(detail).font(mono ? .scaled(11.5, design: .monospaced) : .caption).foregroundStyle(.secondary)
                        .lineLimit(2).truncationMode(.middle)
                }
                if let note {
                    Text(note).font(.scaled(10.5, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).padding(.top, 1)
                }
            }
            Spacer(minLength: 8)
            control
        }
        .padding(.vertical, 10).frame(minHeight: 46)
        .overlay(alignment: .top) { Divider().opacity(first ? 0 : 1) }
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
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.07)))
    }
}

/// A group of a tab: a small uppercase title over a card of rows.
struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.caption2).fontWeight(.semibold).foregroundStyle(.secondary).padding(.leading, 14).padding(.top, 8)
            SettingsTabCard { content }
        }
    }
}

/// A line a page puts at the right of its own header (the Behavior page's note about saving, or why it cannot save).
struct SettingsHeaderNote: Equatable {
    enum Tone { case plain, saved, problem }
    let text: String
    let tone: Tone
}

struct SettingsHeaderNoteKey: PreferenceKey {
    static let defaultValue: SettingsHeaderNote? = nil
    static func reduce(value: inout SettingsHeaderNote?, nextValue: () -> SettingsHeaderNote?) { value = nextValue() ?? value }
}

/// The top of a page: an icon, the title and a line, and the page's note at the right when it has one.
struct SettingsPageHeader: View {
    let page: SettingsPage
    var note: SettingsHeaderNote?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: page.icon)
                .font(.scaled(16, weight: .medium)).foregroundStyle(Color.themeAccent)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.themeAccent.opacity(0.16)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(page.rawValue).font(.title3.weight(.semibold))
                Text(page.detail).font(.callout).foregroundStyle(.secondary)
            }
            if let note {
                Spacer(minLength: 16)
                switch note.tone {
                case .plain: Text(note.text).font(.callout).foregroundStyle(.secondary)
                case .saved: Label(note.text, systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(.green)
                case .problem: Label(note.text, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange)
                }
            }
        }
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
                        Button("Reset", action: reset).buttonStyle(SecondaryCapsuleButtonStyle())
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
            Text("PREVIEW").font(.caption2).fontWeight(.semibold).foregroundStyle(.tertiary)
            content.frame(maxWidth: .infinity)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Divider() }
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
    @AppStorage(AppPreferences.confirmStopKey) private var confirmStop = AppPreferences.defaultConfirmStop
    @AppStorage(AppPreferences.timeStyleKey) private var timeStyle = TimeStyle.relative.rawValue
    @AppStorage(AppPreferences.clockHoursKey) private var clockHours = ClockHours.system.rawValue

    var body: some View {
        SettingsPageBody(reset: { AppPreferences().reset(.general) }) {
            SettingsGroup(title: "Menu bar") {
                SettingsTabRow(title: "Icon style", detail: "What the icon in the menu bar shows", first: true) {
                    // a saved value that is not a style reads as the default, as the icon does
                    Picker("Icon style", selection: Binding(
                        get: { IconStyle(rawValue: style) ?? AppPreferences.defaultStyle },
                        set: { style = $0.rawValue }
                    )) {
                        ForEach(IconStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().fixedSize()
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
                    Picker("Time format", selection: Binding(
                        get: { TimeStyle(rawValue: timeStyle) ?? .relative }, set: { timeStyle = $0.rawValue }
                    )) {
                        Text("Relative").tag(TimeStyle.relative)
                        Text("Clock").tag(TimeStyle.clock)
                    }
                    .labelsHidden().fixedSize()
                }
                SettingsTabRow(title: "Clock", detail: "How clock times count the hours") {
                    Picker("Clock", selection: Binding(
                        get: { ClockHours(rawValue: clockHours) ?? .system }, set: { clockHours = $0.rawValue }
                    )) {
                        Text("System").tag(ClockHours.system)
                        Text("12 hours").tag(ClockHours.h12)
                        Text("24 hours").tag(ClockHours.h24)
                    }
                    .labelsHidden().fixedSize()
                }
                displayPreview()
            }
            SettingsGroup(title: "Confirmations") {
                SettingsTabRow(title: "Ask before stopping Carrier", detail: "Only when stopping would interrupt epics that are running", first: true) {
                    Toggle("Ask before stopping Carrier", isOn: $confirmStop).labelsHidden().toggleStyle(.switch)
                }
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
                    Picker("Color scheme", selection: $colorScheme) {
                        ForEach(ColorSchemeChoice.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
                SettingsTabRow(title: "Text size", detail: "The size of the text of the whole app, \(textSize)%") {
                    Slider(
                        value: Binding(get: { Double(textSize) }, set: { textSize = Int($0) }),
                        in: Double(TypeScale.range.lowerBound)...Double(TypeScale.range.upperBound), step: 5
                    )
                    .frame(width: 160).accessibilityLabel("Text size").accessibilityValue("\(textSize) percent")
                }
                SettingsTabRow(title: "Density", detail: "The space in the sidebar rows and between the messages") {
                    Picker("Density", selection: $density) {
                        ForEach(Density.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
                SettingsTabRow(title: "Message width", detail: "How wide a message gets before it wraps") {
                    Picker("Message width", selection: $messageWidth) {
                        ForEach(MessageWidth.allCases, id: \.self) { Text("\($0.title) · \(Int($0.points)) pt").tag($0) }
                    }
                    .labelsHidden().fixedSize()
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
                    Picker("Font", selection: Binding(
                        get: { MonospaceStyle.installedFamilies.contains(family) ? family : MonospaceSettings.systemFamily },
                        set: { family = $0 }
                    )) {
                        ForEach([MonospaceSettings.systemFamily] + MonospaceStyle.installedFamilies, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
                SettingsTabRow(title: "Size", detail: "\(Int(codeSize)) pt, before the text size of the whole app") {
                    Slider(value: $codeSize, in: Double(MonospaceSettings.sizeRange.lowerBound)...Double(MonospaceSettings.sizeRange.upperBound), step: 1)
                        .frame(width: 160).accessibilityLabel("Code size").accessibilityValue("\(Int(codeSize)) points")
                }
                SettingsTabRow(title: "Line height", detail: "The room between the lines of code and output") {
                    Picker("Line height", selection: $lineHeight) {
                        ForEach(LineHeight.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().fixedSize()
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
                    Picker("Tint the windows", selection: $tint) {
                        ForEach(Tint.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().fixedSize()
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
        Picker(name, selection: selection) { ForEach(options, id: \.self) { Text(title($0)).tag($0) } }.labelsHidden().fixedSize()
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
    @AppStorage(AppPreferences.confirmDeleteKey) private var confirmDelete = AppPreferences.defaultConfirmDelete

    var body: some View {
        SettingsPageBody(reset: { AppPreferences().reset(.chat) }) {
            SettingsGroup(title: "Message box") {
                SettingsTabRow(title: "Send with", detail: "The other key makes a new line", first: true) {
                    Picker("Send with", selection: $sendKey) {
                        Text("Return").tag(SendKey.return)
                        Text("\u{2318}Return").tag(SendKey.commandReturn)
                    }
                    .labelsHidden().fixedSize()
                }
                SettingsTabRow(title: "While the agent works", detail: "What sending does while it answers: hold the message until the turn ends, or stop the turn and send it") {
                    Picker("While the agent works", selection: $whileWorking) {
                        Text("Queue it").tag(WhileWorking.queue)
                        Text("Interrupt").tag(WhileWorking.interrupt)
                    }
                    .labelsHidden().fixedSize()
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
                    Picker("Message times", selection: $messageTimes) {
                        ForEach(MessageTimes.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
                SettingsTabRow(title: "Tool output", detail: "What the agent's tools show: nothing, each run folded, or every call open", first: true) {
                    Picker("Tool output", selection: $toolOutput) {
                        ForEach(ToolOutputMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
                SettingsTabRow(title: "Open the calls that failed", detail: "A call that failed opens by itself, even when the rest are folded") {
                    Toggle("Open the calls that failed", isOn: $opensFailedCalls).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(title: "Diff style", detail: "How an edit reads: its lines one under the other, or removed and added side by side") {
                    Picker("Diff style", selection: $diffStyle) {
                        ForEach(DiffStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
                SettingsTabRow(title: "Output length", detail: "How many lines of an output show before Show more") {
                    Picker("Output length", selection: $outputLength) {
                        ForEach(OutputLength.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
                SettingsTabRow(title: "Show reasoning", detail: "The agent's reasoning, folded under its message, when its host sends it") {
                    Toggle("Show reasoning", isOn: $showsReasoning).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsGroup(title: "Sessions") {
                SettingsTabRow(title: "Ask before deleting a session", detail: "The question says that its worktree is removed with it", first: true) {
                    Toggle("Ask before deleting a session", isOn: $confirmDelete).labelsHidden().toggleStyle(.switch)
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
                    Picker("Remind me again", selection: Binding(
                        get: { ReminderInterval(rawValue: reminder) ?? .never }, set: { reminder = $0.rawValue }
                    )) {
                        ForEach(ReminderInterval.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().fixedSize()
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
                            Button("Open System Settings") { NSWorkspace.shared.open(Self.systemSettingsURL) }
                        }
                        if permission == .notAsked {
                            Button("Allow") { send() }.buttonStyle(PrimaryCapsuleButtonStyle())
                        }
                        Button("Send a test") { send() }.disabled(permission == .noBundle)
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
        return Picker(name, selection: minutes) { ForEach(options, id: \.self) { Text(label($0)).tag($0) } }
            .labelsHidden().fixedSize()
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
