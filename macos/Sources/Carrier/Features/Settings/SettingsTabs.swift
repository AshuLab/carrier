import AppKit
import CarrierCore
import SwiftUI

// The General, Appearance, Sidebar, Chat and Notifications pages of Settings, and what the window's toolbar takes from a screen.
// The pieces a page is built of (rows, groups, selects, fields, the capsule buttons) are under `UI/`.

extension EnvironmentValues {
    /// Where a screen that edits something puts its Save for the toolbar (`SettingsSave`).
    @Entry var settingsSave: SettingsSave?
    /// Where a screen puts a toggle or action button in the toolbar (`SettingsHeaderAction`), such as Pin on a project's page.
    @Entry var settingsHeaderAction: SettingsHeaderAction?
    /// Where a screen puts several action buttons in the toolbar, on one glass capsule (`SettingsHeaderButtons`), such as Check now and Watch a project on Watching.
    @Entry var settingsHeaderButtons: SettingsHeaderButtons?
}

/// The action pills a screen puts in the Settings window's toolbar, side by side on one glass capsule: set while the screen is open, cleared when it goes.
/// Only what is shown is kept (`SettingsHeaderButton`); each one's action is looked up by its title when it is pressed.
@MainActor @Observable final class SettingsHeaderButtons {
    private(set) var buttons: [SettingsHeaderButton] = []
    @ObservationIgnored private var runs: [String: () -> Void] = [:]
    @ObservationIgnored private var owner: UUID?

    func set(_ owner: UUID, _ buttons: [(button: SettingsHeaderButton, run: () -> Void)]) {
        self.owner = owner
        runs = Dictionary(buttons.map { ($0.button.title, $0.run) }, uniquingKeysWith: { first, _ in first })
        if self.buttons != buttons.map(\.button) { self.buttons = buttons.map(\.button) }
    }

    func run(_ title: String) { runs[title]?() }

    /// Only the screen that set them clears them: the next screen may have set its own before this one has gone.
    func clear(_ owner: UUID) {
        guard self.owner == owner else { return }
        self.owner = nil
        runs = [:]
        buttons = []
    }
}

/// A toggle or action pill a screen puts in the Settings window's toolbar (Pin on a project's page): set while the screen is open, cleared when it goes.
@MainActor @Observable final class SettingsHeaderAction {
    private(set) var title: String?
    private(set) var icon = AppIcon.pin
    private(set) var active = false
    private(set) var help = ""
    private(set) var run: (() -> Void)?
    @ObservationIgnored private var owner: UUID?

    func set(_ owner: UUID, title: String, icon: AppIcon, active: Bool, help: String = "", run: @escaping () -> Void) {
        self.owner = owner
        self.title = title
        self.icon = icon
        self.active = active
        self.help = help
        self.run = run
    }

    /// Only the screen that set it clears it: the next screen may have set its own before this one has gone.
    func clear(_ owner: UUID) {
        guard self.owner == owner else { return }
        self.owner = nil
        title = nil
        active = false
        help = ""
        run = nil
    }
}

/// The save of the screen that is open (an account's editor): set by the screen while it has something to save, read by the toolbar's button.
@MainActor @Observable final class SettingsSave {
    private(set) var title: String?
    private(set) var icon = AppIcon.check
    private(set) var enabled = false
    private(set) var run: (() -> Void)?
    @ObservationIgnored private var owner: UUID?

    /// `icon` is the verb's own (Save a check, Add a plus), as the guide gives each button.
    func set(_ owner: UUID, title: String, icon: AppIcon = .check, enabled: Bool, run: @escaping () -> Void) {
        self.owner = owner
        self.title = title
        self.icon = icon
        self.enabled = enabled
        self.run = run
    }

    /// Only the screen that set it clears it: the next one may have set its own before this one has gone.
    func clear(_ owner: UUID) {
        guard self.owner == owner else { return }
        self.owner = nil
        title = nil
        enabled = false
        run = nil
    }
}

/// How wide a field or a slider of a row is, the same on every page so they end and begin on one line down the card.
let settingsSelectWidth: CGFloat = 210

/// How wide a slider of a row is: the width of the selects, which is at least 200 pt, so the track is long enough to aim at.
let settingsSliderWidth: CGFloat = settingsSelectWidth

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

    @AppStorage(Preference.menuIconStyle) private var style
    @AppStorage(Preference.menuAnimate) private var animates
    @AppStorage(Preference.menuShowEpics) private var showsEpics
    @AppStorage(Preference.displayTimeStyle) private var timeStyle
    @AppStorage(Preference.displayClock) private var clockHours

    var body: some View {
        SettingsPageBody(reset: { AppPreferences().reset(.general) }) {
            SettingsGroup(id: "menu-bar", title: "Menu bar") {
                SettingsTabRow(id: "icon-style", title: "Icon style", detail: "What the icon in the menu bar shows", first: true) {
                    ChoicePopUp(
                        label: "Icon style", options: IconStyle.allCases.map { (value: $0, title: $0.title) },
                        selection: $style
                    )
                }
                SettingsTabRow(id: "animate-the-icon", title: "Animate the icon", detail: "A segment moves over the bar while epics run, except in Low Power Mode") {
                    Toggle("Animate the icon", isOn: $animates).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "list-epics-in-the-menu", title: "List epics in the menu", detail: "The epics that run or wait show under the status") {
                    Toggle("List epics in the menu", isOn: $showsEpics).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsGroup(id: "display", title: "Display") {
                SettingsTabRow(id: "time-format", title: "Time format", detail: "Ages read \"11m\" or as a time, \"14:32\"", first: true) {
                    ChoicePopUp(
                        label: "Time format", options: [(value: TimeStyle.relative, title: "Relative"), (value: .clock, title: "Clock")],
                        selection: $timeStyle
                    )
                }
                SettingsTabRow(id: "clock", title: "Clock", detail: "How clock times count the hours") {
                    ChoicePopUp(
                        label: "Clock", options: [(value: ClockHours.system, title: "System"), (value: .h12, title: "12 hours"), (value: .h24, title: "24 hours")],
                        selection: $clockHours
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
    @AppStorage(Preference.appearanceColorScheme) private var colorScheme
    @AppStorage(Preference.appearanceTheme) private var theme
    @AppStorage(Preference.appearanceAccent) private var accentName
    @AppStorage(Preference.appearanceTint) private var tint
    @AppStorage(Preference.appearanceTranslucent) private var translucentChoice
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme
    @AppStorage(Preference.appearanceTextSize) private var textSize
    @AppStorage(Preference.appearanceIconWeight) private var iconWeight
    @AppStorage(Preference.appearanceIconSet) private var iconSet
    @AppStorage(Preference.appearanceDensity) private var density
    @AppStorage(Preference.appearanceMonoFamily) private var family
    @AppStorage(Preference.appearanceMonoSize) private var codeSize
    @AppStorage(Preference.appearanceMonoLineHeight) private var lineHeight
    @AppStorage(Preference.appearanceMonoLigatures) private var ligatures
    @AppStorage(Preference.appearanceMonoWrap) private var wrapLongLines
    @AppStorage(Preference.appearanceMonoLineNumbers) private var lineNumbers

    private var accent: Binding<AccentColor?> {
        Binding(get: { accentName.flatMap(AccentColor.init(rawValue:)) }, set: { accentName = $0?.rawValue })
    }

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

    /// A few of the icons as they are drawn now, larger than in a row so the stroke the weight sets can be seen.
    private var iconsPreview: some View {
        SettingsPreview {
            // wraps when the text size and the window leave less than the ten icons need in a row
            FlowLayout(spacing: 22) {
                ForEach([AppIcon.search, .settings, .folder, .copy, .bell, .trash, .refresh, .lock, .microphone, .terminal], id: \.self) { Glyph($0, size: 22) }
            }
            .foregroundStyle(.primary).frame(maxWidth: .infinity)
        }
    }

    @AppStorage(Preference.appearanceStatesByShape) private var statesByShape
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
            SettingsGroup(id: "theme", title: "Theme") {
                ThemeGallery(theme: $theme)
            }
            SettingsGroup(id: "look", title: "Look") {
                SettingsTabRow(id: "color-scheme", title: "Color scheme", detail: "System follows the Mac", first: true) {
                    ChoicePopUp(label: "Color scheme", options: ColorSchemeChoice.allCases.map { (value: $0, title: $0.title) }, selection: $colorScheme)
                }
                SettingsTabRow(id: "text-size", title: "Text size", detail: "The size of the text of the interface, \(textSize)%; the messages have their own in Chat") {
                    Slider(
                        value: Binding(get: { Double(textSize) }, set: { textSize = Int($0) }),
                        in: Double(TypeScale.range.lowerBound)...Double(TypeScale.range.upperBound), step: 5
                    )
                    .labelsHidden().frame(width: settingsSliderWidth).accessibilityLabel("Text size").accessibilityValue("\(textSize) percent")
                }
                SettingsTabRow(id: "icon-set", title: "Icon set", detail: "The look of the icons of the app: SF Symbols are the Mac's own") {
                    ChoicePopUp(
                        label: "Icon set", options: IconSet.allCases.map { (value: $0, title: $0.title) },
                        selection: $iconSet
                    )
                }
                SettingsTabRow(id: "icon-weight", title: "Icon weight", detail: "How thick the strokes of the icons are, \(iconWeight.formatted(.number.precision(.fractionLength(0...2))))") {
                    Slider(value: $iconWeight, in: IconWeight.range, step: IconWeight.step)
                        .labelsHidden().frame(width: settingsSliderWidth)
                        .accessibilityLabel("Icon weight").accessibilityValue(iconWeight.formatted(.number.precision(.fractionLength(0...2))))
                }
                iconsPreview
                SettingsTabRow(id: "density", title: "Density", detail: "The space in the sidebar rows") {
                    ChoicePopUp(label: "Density", options: Density.allCases.map { (value: $0, title: $0.title) }, selection: $density)
                }
                SettingsTabRow(id: "tell-states-apart-by-shape", title: "Tell states apart by shape", detail: "A symbol in each state, so that color is not the only clue") {
                    Toggle("Tell states apart by shape", isOn: $statesByShape).labelsHidden().toggleStyle(.switch)
                }
                statesPreview
            }
            SettingsGroup(id: "color", title: "Color") {
                SettingsTabRow(id: "accent-color", title: "Accent color", detail: "Buttons, switches and the selection", first: true) {
                    AccentSwatches(theme: theme, scheme: scheme == .dark ? .dark : .light, accent: accent)
                }
                SettingsTabRow(id: "tint-the-windows", title: "Tint the windows", detail: "A touch of the theme's own color on the backgrounds") {
                    ChoicePopUp(label: "Tint the windows", options: Tint.allCases.map { (value: $0, title: $0.title) }, selection: $tint)
                }
                SettingsTabRow(id: "translucent-windows", title: "Translucent windows", detail: "Off draws solid backgrounds") {
                    Toggle("Translucent windows", isOn: Binding(
                        get: { translucentChoice ?? (reduceTransparency == false) }, set: { translucentChoice = $0 }
                    ))
                    .labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsGroup(id: "code-and-output", title: "Code and output") {
                SettingsTabRow(id: "font", title: "Font", detail: "The monospaced fonts installed on this Mac", first: true) {
                    // a family that is no longer installed shows as the system's, as the views draw it
                    ChoicePopUp(
                        label: "Font", options: ([MonospaceSettings.systemFamily] + MonospaceStyle.installedFamilies).map { (value: $0, title: $0) },
                        selection: Binding(
                            get: { MonospaceStyle.installedFamilies.contains(family) ? family : MonospaceSettings.systemFamily },
                            set: { family = $0 }
                        )
                    )
                }
                SettingsTabRow(id: "size", title: "Size", detail: "In points, before the text size of the whole app") {
                    Slider(value: $codeSize, in: Double(MonospaceSettings.sizeRange.lowerBound)...Double(MonospaceSettings.sizeRange.upperBound), step: 1)
                        .labelsHidden().frame(width: settingsSliderWidth).accessibilityLabel("Code size").accessibilityValue("\(Int(codeSize)) points")
                }
                SettingsTabRow(id: "line-height", title: "Line height", detail: "The room between the lines of code and output") {
                    ChoicePopUp(label: "Line height", options: LineHeight.allCases.map { (value: $0, title: $0.title) }, selection: $lineHeight)
                }
                SettingsTabRow(id: "ligatures", title: "Ligatures", detail: "Joins pairs such as != and >= where the font has them") {
                    Toggle("Ligatures", isOn: $ligatures).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "wrap-long-lines", title: "Wrap long lines", detail: "Off keeps each line whole and scrolls sideways") {
                    Toggle("Wrap long lines", isOn: $wrapLongLines).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "line-numbers", title: "Line numbers", detail: "In code blocks and the output of a command") {
                    Toggle("Line numbers", isOn: $lineNumbers).labelsHidden().toggleStyle(.switch)
                }
                codePreview()
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
                        Text(option.title).font(.scaled(12))
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

/// Opens the Mac's color panel and tells what the person picks in it, until another place opens it.
@MainActor private final class ColorPanelOpener: NSObject {
    static let shared = ColorPanelOpener()
    private var picked: ((NSColor) -> Void)?

    func open(color: NSColor, picked: @escaping (NSColor) -> Void) {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.isFloatingPanel = true
        // set before the target, so showing the current color does not count as a pick
        panel.color = color
        self.picked = picked
        panel.setTarget(self)
        panel.setAction(#selector(changed(_:)))
        NSApp.activate()
        if panel.isVisible == false { place(panel, besides: NSEvent.mouseLocation) }
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    @objc private func changed(_ panel: NSColorPanel) { picked?(panel.color) }

    /// The panel has no place of its own the first time: next to the click, on the side with room, so the page it changes stays in sight.
    private func place(_ panel: NSColorPanel, besides point: NSPoint) {
        let room = (NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main)?.visibleFrame ?? .zero
        let size = panel.frame.size
        var x = point.x + 24
        if x + size.width > room.maxX { x = point.x - size.width - 24 }
        let y = min(max(point.y - size.height / 2, room.minY), room.maxY - size.height)
        panel.setFrameOrigin(NSPoint(x: max(x, room.minX), y: y))
    }
}

/// The theme's own accent, a line, the seven colors and a multicolor disc that opens the Mac's color panel, as discs; the chosen one has a ring.
/// The line says the first is the theme's and the others are choices of the person.
private struct AccentSwatches: View {
    let theme: Theme
    let scheme: ThemeScheme
    @Binding var accent: AccentColor?

    var body: some View {
        HStack(spacing: 8) {
            swatch("\(theme.title) accent", color: themeSurfaces(theme, scheme: scheme, translucent: false).accent.map(Color.init) ?? .accentColor, chosen: accent == nil) { accent = nil }
            SettingsDivider(vertical: true).frame(height: 18).padding(.horizontal, 4)
            ForEach(AccentColor.allCases, id: \.self) { option in
                swatch(option.title, color: Color(option.color), chosen: accent == option) { accent = option }
            }
            customSwatch
        }
    }

    /// A disc of every hue that opens the Mac's own color panel; once a color is picked, it fills the middle of the disc.
    private var customSwatch: some View {
        let chosen = accent?.isCustom == true
        return Button {
            ColorPanelOpener.shared.open(color: accent.map { NSColor(Color($0.color)) } ?? .controlAccentColor) { picked in
                guard let rgb = picked.usingColorSpace(.sRGB) else { return }
                accent = .own(RGBA(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent))
            }
        } label: {
            ZStack {
                Circle().fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                if let accent, chosen { Circle().fill(Color(accent.color)).padding(4) }
            }
            .frame(width: 18, height: 18)
            .padding(3).overlay(Circle().strokeBorder(chosen ? Color.primary.opacity(0.7) : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain).help("Custom color").accessibilityLabel("Custom accent color").accessibilityAddTraits(chosen ? .isSelected : [])
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
    @AppStorage(Preference.sidebarGroupBy) private var groupBy
    @AppStorage(Preference.sidebarSessionSort) private var sessionSort
    @AppStorage(Preference.sidebarArchiveSort) private var archiveSort
    @AppStorage(Preference.sidebarRowIcon) private var showsIcon
    @AppStorage(Preference.sidebarRowBranch) private var showsBranch
    @AppStorage(Preference.sidebarRowPullRequest) private var showsPullRequest
    @AppStorage(Preference.sidebarRowDiff) private var showsDiff
    @AppStorage(Preference.sidebarRowProviders) private var showsProviders
    @AppStorage(Preference.sidebarRowAge) private var showsAge

    /// Sessions of the preview: each has a branch, two providers and an age, so each switch has something to hide; one is finished and one waits,
    /// which is where "Done" and "Needs you" take the age's place, and one has a pull request and one only the lines it changed: each gives the row its third line.
    private static let samples = [
        ("preview-idle", "Fix the flaky login test", SessionState.idle, false, -11, SessionPullRequest?.none),
        ("preview-done", "Add the retry to uploads", .idle, true, -3, SessionPullRequest(number: 412, url: "https://github.com/AshuLab/carrier/pull/412", state: .open, checks: .passing)),
        ("preview-waiting", "Rename the billing module", .waiting, false, -26, nil),
    ].map { id, title, state, unread, minutes, pullRequest in
        SessionRow(
            id: id, title: title, workspace: "carrier", agent: "claude", state: state, updatedAt: Date(timeIntervalSinceNow: Double(minutes) * 60),
            branch: "fix/login-flake", folder: "/preview", providers: ["claude", "codex"], unread: unread,
            diff: pullRequest == nil ? (state == .idle && unread == false ? SessionDiff(added: 12, removed: 3) : nil) : SessionDiff(added: 86, removed: 12), pullRequest: pullRequest
        )
    }

    var body: some View {
        SettingsPageBody(reset: { AppPreferences().reset(.sidebar) }) {
            SettingsGroup(id: "order", title: "Order") {
                SettingsTabRow(id: "group-epics-by", title: "Group epics by", detail: "How the epics under Carrier are grouped", first: true) {
                    picker("Group epics by", selection: $groupBy, options: GroupBy.allCases) { $0.title }
                }
                SettingsTabRow(id: "sort-sessions", title: "Sort sessions", detail: "How the Sessions list is grouped and ordered") {
                    picker("Sort sessions", selection: $sessionSort, options: SessionSort.allCases) { $0.title }
                }
                SettingsTabRow(id: "sort-the-archive", title: "Sort the Archive", detail: "How the archived sessions are ordered") {
                    picker("Sort the Archive", selection: $archiveSort, options: ArchiveSort.allCases) { $0.title }
                }
            }
            SettingsGroup(id: "session-rows", title: "Session rows") {
                SettingsTabRow(id: "project-icon", title: "Project icon", detail: "The colored square with the project's initials", first: true) {
                    Toggle("Project icon", isOn: $showsIcon).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "branch", title: "Branch", detail: "Where the session works, the branch or the base folder") {
                    Toggle("Branch", isOn: $showsBranch).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "pull-request", title: "Pull request", detail: "The pull request of the session's branch, with its state and how its checks went, on a third line") {
                    Toggle("Pull request", isOn: $showsPullRequest).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "lines-changed", title: "Lines changed", detail: "How many lines the session added and removed, on the third line with or without a pull request") {
                    Toggle("Lines changed", isOn: $showsDiff).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "providers", title: "Providers", detail: "The marks of the providers the session used") {
                    Toggle("Providers", isOn: $showsProviders).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "age", title: "Age", detail: "How long ago the session was last active; Done and Needs you take its place, and so do Pin and Archive on hover") {
                    Toggle("Age", isOn: $showsAge).labelsHidden().toggleStyle(.switch)
                }
                SettingsPreview {
                    VStack(spacing: 0) {
                        ForEach(Self.samples, id: \.id) { SessionRowView(row: $0, showsWorkspace: true, roomy: true).allowsHitTesting(false) }
                    }
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
    @AppStorage(Preference.chatSendKey) private var sendKey
    @AppStorage(Preference.chatWhileWorking) private var whileWorking
    @AppStorage(Preference.chatWritingTools) private var writingTools
    @AppStorage(Preference.chatCheckSpelling) private var checksSpelling
    @AppStorage(Preference.chatCorrectSpelling) private var correctsSpelling
    @AppStorage(Preference.chatShowsContextUsage) private var showsContextUsage
    @AppStorage(Preference.chatFollowOutput) private var followsOutput
    @AppStorage(Preference.chatMessageTimes) private var messageTimes
    @AppStorage(Preference.chatToolOutput) private var toolOutput
    @AppStorage(Preference.chatOpensFailedCalls) private var opensFailedCalls
    @AppStorage(Preference.chatDiffStyle) private var diffStyle
    @AppStorage(Preference.chatOutputLength) private var outputLines
    @AppStorage(Preference.chatShowReasoning) private var showsReasoning
    @AppStorage(Preference.appearanceMessageWidth) private var messageWidth
    @AppStorage(Preference.chatSurface) private var chatSurface
    @AppStorage(Preference.chatTextSize) private var textSize
    @AppStorage(Preference.chatLineSpacing) private var lineSpacing
    @AppStorage(Preference.chatMessageSpacing) private var messageSpacing
    @State private var previewRoom: CGFloat = 0
    @State private var flipped: Set<String> = []

    /// The column of a conversation as the person set it, drawn with the feed's own rows (a message of theirs, the agent's work, its answer) in the
    /// middle of a track that is the widest column: the column is to the track as the chosen width is to the widest one, so the four differ in
    /// where the lines break and in how much of the track they take.
    private var messagePreview: some View {
        SettingsPreview {
            VStack(alignment: .leading, spacing: messageSpacing.gap) {
                ForEach(sampleConversation()) { row in
                    FeedRowView(
                        row: row, time: nil, summary: nil, pinned: false, flipped: $flipped, agent: "claude", commands: [], offersWayOut: false,
                        work: WorkState(live: false, waiting: false, since: nil)
                    )
                }
            }
            .padding(.vertical, 12)
            .frame(width: previewRoom * messageWidth.points / MessageWidth.widest.points, alignment: .leading)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { previewRoom = $0 }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        }
    }

    var body: some View {
        SettingsPageBody(reset: { AppPreferences().reset(.chat) }) {
            SettingsGroup(id: "message-box", title: "Message box") {
                SettingsTabRow(id: "send-with", title: "Send with", detail: "The other key makes a new line", first: true) {
                    ChoicePopUp(label: "Send with", options: [(value: SendKey.return, title: "Return"), (value: .commandReturn, title: "\u{2318}Return")], selection: $sendKey)
                }
                SettingsTabRow(id: "while-the-agent-works", title: "While the agent works", detail: "Hold the message, or stop the turn and send it") {
                    ChoicePopUp(label: "While the agent works", options: [(value: WhileWorking.queue, title: "Queue it"), (value: .interrupt, title: "Interrupt")], selection: $whileWorking)
                }
                SettingsTabRow(id: "writing-tools", title: "Writing Tools", detail: "The system's offer to rewrite or proofread what you select") {
                    Toggle("Writing Tools", isOn: $writingTools).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "check-spelling", title: "Check spelling", detail: "Underline words that look misspelled") {
                    Toggle("Check spelling", isOn: $checksSpelling).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "correct-spelling-automatically", title: "Correct spelling automatically", detail: "Fix a misspelled word as you type it") {
                    Toggle("Correct spelling automatically", isOn: $correctsSpelling).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "context-and-limits", title: "Context and limits", detail: "A ring beside the microphone: how full the context is and how much of the 5h limit is used") {
                    Toggle("Context and limits", isOn: $showsContextUsage).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsGroup(id: "conversation", title: "Conversation") {
                SettingsTabRow(id: "follow-new-output", title: "Follow new output", detail: "Scroll to what arrives while you are at the end", first: true) {
                    Toggle("Follow new output", isOn: $followsOutput).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "message-times", title: "Message times", detail: "When a message shows the time it was written, as in General") {
                    ChoicePopUp(label: "Message times", options: MessageTimes.allCases.map { (value: $0, title: $0.title) }, selection: $messageTimes)
                }
                SettingsTabRow(id: "tool-output", title: "Tool output", detail: "Nothing, each run folded, or every call open") {
                    ChoicePopUp(label: "Tool output", options: ToolOutputMode.allCases.map { (value: $0, title: $0.title) }, selection: $toolOutput)
                }
                SettingsTabRow(id: "open-the-calls-that-failed", title: "Open the calls that failed", detail: "A call that failed opens by itself, even when the rest are folded") {
                    Toggle("Open the calls that failed", isOn: $opensFailedCalls).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "diff-style", title: "Diff style", detail: "Unified, or removed and added side by side") {
                    ChoicePopUp(label: "Diff style", options: DiffStyle.allCases.map { (value: $0, title: $0.title) }, selection: $diffStyle)
                }
                SettingsTabRow(id: "output-length", title: "Output length", detail: "How many lines of an output show before Show more") {
                    ChoicePopUp(label: "Output length", options: OutputLength.allCases.map { (value: $0, title: $0.title) }, selection: Binding(get: { OutputLength(rawValue: outputLines) ?? AppPreferences.defaultOutputLength }, set: { outputLines = $0.rawValue }))
                }
                SettingsTabRow(id: "show-reasoning", title: "Show reasoning", detail: "The agent's reasoning, folded under its message, when its host sends it") {
                    Toggle("Show reasoning", isOn: $showsReasoning).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "message-text-size", title: "Message text size", detail: "The size of the text of the messages, \(Int(textSize)) pt, apart from the text size of the app") {
                    Slider(value: $textSize, in: Double(ChatText.sizeRange.lowerBound)...Double(ChatText.sizeRange.upperBound), step: 1)
                        .labelsHidden().frame(width: settingsSliderWidth).accessibilityLabel("Message text size").accessibilityValue("\(Int(textSize)) points")
                }
                SettingsTabRow(id: "line-spacing", title: "Line spacing", detail: "The room between the lines of a message") {
                    ChoicePopUp(label: "Line spacing", options: ChatLineSpacing.allCases.map { (value: $0, title: $0.title) }, selection: $lineSpacing)
                }
                SettingsTabRow(id: "message-spacing", title: "Message spacing", detail: "The room between the messages") {
                    ChoicePopUp(label: "Message spacing", options: MessageSpacing.allCases.map { (value: $0, title: $0.title) }, selection: $messageSpacing)
                }
                SettingsTabRow(id: "message-width", title: "Message width", detail: "How wide a message gets before it wraps") {
                    ChoicePopUp(
                        label: "Message width", options: MessageWidth.allCases.map { (value: $0, title: "\($0.title) · \(Int($0.points)) pt") },
                        selection: $messageWidth
                    )
                }
                SettingsTabRow(id: "surfaces", title: "Surfaces", detail: "Glass blurs what is under; flat is a quiet solid fill") {
                    SegmentedChoice(options: ChatSurface.allCases.map { (value: $0, title: $0.title, icon: nil) }, selection: $chatSurface)
                }
                messagePreview
            }
        }
    }
}

struct NotificationsTabView: View {
    let centre: any NotificationCentre
    let reader: any NotificationPermissionReader
    @AppStorage(Preference.notifyNeedsYou) private var needsYou
    @AppStorage(Preference.notifyReadyForTest) private var readyForTest
    @AppStorage(Preference.notifyProblem) private var problem
    @AppStorage(Preference.notifyChatNeedsAttention) private var chatNeedsAttention
    @AppStorage(Preference.notifyChatDone) private var chatDone
    @AppStorage(Preference.notifyOnlyWhenAway) private var onlyWhenAway
    @AppStorage(Preference.notifyDockBadge) private var dockBadge
    @AppStorage(Preference.notifySound) private var sound
    @AppStorage(Preference.notifyReminder) private var reminder
    @AppStorage(Preference.notifyQuiet) private var quiet
    @AppStorage(Preference.notifyQuietStart) private var quietStart
    @AppStorage(Preference.notifyQuietEnd) private var quietEnd
    @State private var permission: NotificationPermission?
    @State private var testAdvice: String?

    var body: some View {
        SettingsPageBody(reset: { AppPreferences().reset(.notifications) }) {
            SettingsGroup(id: "carrier", title: "Carrier") {
                SettingsTabRow(id: "needs-attention", title: "Needs attention", detail: "An epic stopped and waits for a person", first: true) {
                    Toggle("Needs attention", isOn: $needsYou).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "ready-for-test", title: "Ready for test", detail: "An epic finished and has a PR to try") {
                    Toggle("Ready for test", isOn: $readyForTest).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "a-problem", title: "A problem", detail: "GitHub refuses a repo, or Carrier stops by itself") {
                    Toggle("A problem", isOn: $problem).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsGroup(id: "chat", title: "Chat") {
                SettingsTabRow(id: "needs-attention", title: "Needs attention", detail: "A session waits for an approval", first: true) {
                    Toggle("Chat needs attention", isOn: $chatNeedsAttention).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "done", title: "Done", detail: "A session finished its turn") {
                    Toggle("Chat done", isOn: $chatDone).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsGroup(id: "delivery", title: "Delivery") {
                SettingsTabRow(id: "only-when-carrier-is-not-in-front", title: "Only when Carrier is not in front", detail: "No banner while its window is the one you are looking at", first: true) {
                    Toggle("Only when Carrier is not in front", isOn: $onlyWhenAway).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "dock-badge", title: "Dock badge", detail: "The Dock icon counts the epics that need a person and the sessions that wait for an approval") {
                    Toggle("Dock badge", isOn: $dockBadge).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "play-a-sound", title: "Play a sound", detail: "A banner plays the notification sound") {
                    Toggle("Play a sound", isOn: $sound).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "remind-me-again", title: "Remind me again", detail: "While an epic or a session still needs attention. Ready for test and Done never remind") {
                    // a saved value that is not a choice reads as Never, as the watcher does
                    ChoicePopUp(
                        label: "Remind me again", options: ReminderInterval.allCases.map { (value: $0, title: $0.title) },
                        selection: Binding(get: { ReminderInterval(rawValue: reminder) ?? .never }, set: { reminder = $0.rawValue })
                    )
                }
                SettingsTabRow(id: "quiet-hours", title: "Quiet hours", detail: "No banner and no sound: notifications wait in the Notification Center") {
                    Toggle("Quiet hours", isOn: $quiet).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "from", title: "From", detail: "When the quiet starts") {
                    timePicker("From", $quietStart)
                }
                .disabled(quiet == false)
                SettingsTabRow(id: "until", title: "Until", detail: "When it ends, the next day if it is earlier than the start") {
                    timePicker("Until", $quietEnd)
                }
                .disabled(quiet == false)
            }
            SettingsGroup(id: "permission", title: "Permission") {
                SettingsTabRow(id: "system-permission", title: "System permission", detail: permission?.text ?? "Checking…", first: true) {
                    HStack {
                        if permission != .noBundle {
                            Button { NSWorkspace.shared.open(Self.systemSettingsURL) } label: { Label("Open System Settings", icon: .settings) }
                        }
                        if permission == .notAsked {
                            Button { send() } label: { Label("Allow", icon: .check) }.buttonStyle(PrimaryCapsuleButtonStyle())
                        }
                        Button { send() } label: { Label("Send a test", icon: .send) }.disabled(permission == .noBundle)
                    }
                }
            }
            if let testAdvice {
                Label(testAdvice, icon: .warningFilled).font(.scaled(12)).foregroundStyle(.orange).padding(.horizontal, 14)
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
        centre.sendTest()
    }

    private func refresh() {
        readPermission(bundleIdentifier: Bundle.main.bundleIdentifier, reader: reader) {
            permission = $0
            if $0.testAdvice == nil { testAdvice = nil }
        }
    }
}


