import AppKit
import CarrierCore
import SwiftUI

/// Settings page for the embedded Ghostty terminal: theme, minimum contrast, padding, typography overrides, cursor and Zsh behavior.
struct TerminalTabView: View {
    @AppStorage(Preference.appearanceColorScheme) private var colorScheme
    @AppStorage(Preference.appearanceTheme) private var appTheme
    @AppStorage(Preference.appearanceAccent) private var accentName
    @AppStorage(Preference.appearanceTint) private var tint
    @AppStorage(Preference.appearanceTranslucent) private var translucentChoice
    @AppStorage(Preference.appearanceMonoFamily) private var appFontFamily
    @AppStorage(Preference.appearanceMonoSize) private var appFontSize
    @AppStorage(Preference.appearanceMonoLigatures) private var appLigatures

    @AppStorage(Preference.terminalTheme) private var themeOverride
    @AppStorage(Preference.terminalFontFamily) private var fontFamilyOverride
    @AppStorage(Preference.terminalFontLigatures) private var fontLigaturesOverride
    @AppStorage(Preference.terminalFontThicken) private var fontThicken
    @AppStorage(Preference.terminalCursorStyle) private var cursorStyle
    @AppStorage(Preference.terminalCursorBlink) private var cursorBlink
    @AppStorage(Preference.terminalPaddingX) private var paddingX
    @AppStorage(Preference.terminalPaddingY) private var paddingY
    @AppStorage(Preference.terminalMinimumContrast) private var minimumContrast
    @AppStorage(Preference.terminalPanesDimInactive) private var dimInactivePanes
    @AppStorage(Preference.terminalPanesFocusFollowsMouse) private var focusFollowsMouse
    @AppStorage(Preference.terminalInputOptionAsAlt) private var optionAsAlt
    @AppStorage(Preference.terminalInputCopyOnSelect) private var copyOnSelect
    @AppStorage(Preference.terminalScrollbackLimit) private var scrollbackLimitRaw
    @AppStorage(Preference.terminalConfirmCloseRunningProcess) private var confirmCloseRunningProcess
    @AppStorage(Preference.terminalPinPromptToBottom) private var pinPromptToBottom

    @State private var fontSizeOverride = AppPreferences().value(Preference.terminalFontSize)

    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var accent: AccentColor? { accentName.flatMap(AccentColor.init(rawValue:)) }

    private var fontFamilySelection: Binding<String?> {
        Binding(
            get: { TerminalSettings.cleanFontFamily(fontFamilyOverride) },
            set: { fontFamilyOverride = TerminalSettings.cleanFontFamily($0) }
        )
    }

    private var fontSizeSelection: Binding<Int?> {
        Binding(
            get: {
                guard let fontSizeOverride, fontSizeOverride.isFinite else { return nil }
                return Int(TerminalSettings.clampFontSize(fontSizeOverride).rounded())
            },
            set: { newValue in
                if let newValue {
                    let clamped = TerminalSettings.clampFontSize(Double(newValue))
                    AppPreferences().store(clamped, for: Preference.terminalFontSize)
                    fontSizeOverride = clamped
                } else {
                    AppPreferences().store(nil, for: Preference.terminalFontSize)
                    fontSizeOverride = nil
                }
            }
        )
    }

    private var minimumContrastSelection: Binding<Double> {
        Binding(
            get: { minimumContrast },
            set: { minimumContrast = TerminalSettings.clampMinimumContrast(($0 * 2).rounded() / 2) }
        )
    }

    private var paddingXSelection: Binding<Double> {
        Binding(
            get: { paddingX },
            set: { paddingX = TerminalSettings.clampPadding($0.rounded()) }
        )
    }

    private var paddingYSelection: Binding<Double> {
        Binding(
            get: { paddingY },
            set: { paddingY = TerminalSettings.clampPadding($0.rounded()) }
        )
    }

    private var scrollbackLimitSelection: Binding<TerminalScrollbackLimit> {
        Binding(
            get: { TerminalScrollbackLimit(rawValue: scrollbackLimitRaw) ?? TerminalSettings.defaultScrollbackLimit },
            set: { scrollbackLimitRaw = $0.rawValue }
        )
    }

    private var resolvedScheme: ThemeScheme {
        TerminalAppearanceMapper.resolveScheme(colorScheme, system: systemColorScheme)
    }

    private var currentSettings: TerminalSettings {
        TerminalSettings(
            themeOverride: themeOverride,
            fontFamilyOverride: fontFamilyOverride,
            fontSizeOverride: fontSizeOverride,
            fontLigaturesOverride: fontLigaturesOverride,
            fontThicken: fontThicken,
            cursorStyle: cursorStyle,
            cursorBlink: cursorBlink,
            paddingX: paddingX,
            paddingY: paddingY,
            minimumContrast: minimumContrast,
            dimInactivePanes: dimInactivePanes,
            focusFollowsMouse: focusFollowsMouse,
            optionAsAlt: optionAsAlt,
            copyOnSelect: copyOnSelect,
            scrollbackLimit: scrollbackLimitSelection.wrappedValue,
            confirmCloseRunningProcess: confirmCloseRunningProcess,
            pinPromptToBottom: pinPromptToBottom
        )
    }

    private var previewProfile: TerminalAppearanceProfile {
        let monospace = MonospaceSettings(
            family: appFontFamily,
            size: CGFloat(appFontSize.rounded()),
            ligatures: appLigatures
        )
        let effectiveTranslucent = translucentChoice ?? (reduceTransparency == false)
        return TerminalAppearanceProfile(
            theme: appTheme,
            scheme: resolvedScheme,
            accent: accent,
            tint: tint,
            translucent: effectiveTranslucent,
            monospace: monospace,
            terminalSettings: currentSettings
        )
    }

    private var themeOptions: [(value: Theme?, title: String)] {
        [(value: nil, title: "Same as app (\(appTheme.title))")]
            + Theme.allCases.map { (value: $0, title: $0.title) }
    }

    private var appFontDisplayName: String {
        TerminalSettings.cleanFontFamily(appFontFamily) ?? MonospaceSettings.systemFamily
    }

    private var fontFamilyOptions: [(value: String?, title: String)] {
        let families = TerminalSettings.availableFontFamilies(
            installed: MonospaceStyle.installedFamilies,
            currentOverride: fontFamilyOverride
        )
        return [(value: nil, title: "Same as Appearance (\(appFontDisplayName))")]
            + families.map { (value: $0, title: $0) }
    }

    private var fontSizeOptions: [(value: Int?, title: String)] {
        let sizes = TerminalSettings.availableFontSizes(currentOverride: fontSizeOverride)
        return [(value: nil, title: "Same as Appearance (\(Int(appFontSize.rounded())) pt)")]
            + sizes.map { (value: $0, title: "\($0) pt") }
    }

    private var ligaturesOptions: [(value: Bool?, title: String)] {
        [
            (value: nil, title: "Same as Appearance (\(appLigatures ? "On" : "Off"))"),
            (value: true, title: "On"),
            (value: false, title: "Off"),
        ]
    }

    private var cursorStyleOptions: [(value: TerminalCursorStyleChoice, title: String, icon: AppIcon?)] {
        TerminalCursorStyleChoice.allCases.map { (value: $0, title: $0.title, icon: nil) }
    }

    private var optionAsAltOptions: [(value: TerminalOptionAsAlt, title: String)] {
        TerminalOptionAsAlt.allCases.map { (value: $0, title: $0.title) }
    }

    private var scrollbackLimitOptions: [(value: TerminalScrollbackLimit, title: String)] {
        TerminalScrollbackLimit.allCases.map { (value: $0, title: $0.title) }
    }

    var body: some View {
        SettingsPageBody(reset: resetTerminalSettings) {
            SettingsGroup(title: "Appearance") {
                SettingsTabRow(title: "Theme", detail: "Color palette for panes; inherits the app theme by default", first: true) {
                    ChoicePopUp(label: "Theme", options: themeOptions, selection: $themeOverride)
                }
                SettingsTabRow(
                    title: "Minimum contrast",
                    detail: "Raises low-contrast ANSI text · \(TerminalSettings.minimumContrastLabel(minimumContrast))"
                ) {
                    Slider(value: minimumContrastSelection, in: TerminalSettings.minimumContrastRange)
                        .labelsHidden().frame(width: settingsSliderWidth)
                        .accessibilityLabel("Minimum contrast")
                        .accessibilityValue(TerminalSettings.minimumContrastLabel(minimumContrast))
                }
                SettingsTabRow(
                    title: "Horizontal padding",
                    detail: "Left and right margin inside each pane · \(Int(paddingX.rounded())) pt"
                ) {
                    Slider(value: paddingXSelection, in: TerminalSettings.paddingRange)
                        .labelsHidden().frame(width: settingsSliderWidth)
                        .accessibilityLabel("Horizontal padding")
                        .accessibilityValue("\(Int(paddingX.rounded())) points")
                }
                SettingsTabRow(
                    title: "Vertical padding",
                    detail: "Top and bottom margin inside each pane · \(Int(paddingY.rounded())) pt"
                ) {
                    Slider(value: paddingYSelection, in: TerminalSettings.paddingRange)
                        .labelsHidden().frame(width: settingsSliderWidth)
                        .accessibilityLabel("Vertical padding")
                        .accessibilityValue("\(Int(paddingY.rounded())) points")
                }
                SettingsPreview {
                    TerminalSettingsPreview(profile: previewProfile, pinPromptToBottom: pinPromptToBottom)
                }
            }

            SettingsGroup(title: "Typography") {
                SettingsTabRow(
                    title: "Font",
                    detail: "Monospaced font used in panes; inherits Appearance › Code and output",
                    first: true
                ) {
                    ChoicePopUp(label: "Font", options: fontFamilyOptions, selection: fontFamilySelection)
                }
                SettingsTabRow(title: "Size", detail: "Text size in points for terminal output") {
                    ChoicePopUp(label: "Size", options: fontSizeOptions, selection: fontSizeSelection)
                }
                SettingsTabRow(title: "Ligatures", detail: "Joins pairs such as != and >= where the font has them") {
                    ChoicePopUp(label: "Ligatures", options: ligaturesOptions, selection: $fontLigaturesOverride)
                }
                SettingsTabRow(title: "Thicken font", detail: "Renders glyphs slightly heavier on Retina displays") {
                    Toggle("Thicken font", isOn: $fontThicken).labelsHidden().toggleStyle(.switch)
                }
            }

            SettingsGroup(title: "Cursor") {
                SettingsTabRow(title: "Cursor style", detail: "Shape of the text cursor inside terminal panes", first: true) {
                    SegmentedChoice(options: cursorStyleOptions, selection: $cursorStyle)
                }
                SettingsTabRow(title: "Blink cursor", detail: "Animates the cursor when the pane is focused") {
                    Toggle("Blink cursor", isOn: $cursorBlink).labelsHidden().toggleStyle(.switch)
                }
            }

            SettingsGroup(title: "Panes") {
                SettingsTabRow(
                    title: "Dim inactive panes",
                    detail: "Softens unfocused split panes so the active pane stands out",
                    first: true
                ) {
                    Toggle("Dim inactive panes", isOn: $dimInactivePanes).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(
                    title: "Focus follows mouse",
                    detail: "Activates split panes when hovering over them without clicking"
                ) {
                    Toggle("Focus follows mouse", isOn: $focusFollowsMouse).labelsHidden().toggleStyle(.switch)
                }
            }

            SettingsGroup(title: "Input and scrollback") {
                SettingsTabRow(
                    title: "Option as Alt",
                    detail: "Sends Option key presses as Meta/Alt escape sequences in shells",
                    first: true
                ) {
                    ChoicePopUp(label: "Option as Alt", options: optionAsAltOptions, selection: $optionAsAlt)
                }
                SettingsTabRow(
                    title: "Copy on select",
                    detail: "Copies highlighted terminal text to the clipboard automatically"
                ) {
                    Toggle("Copy on select", isOn: $copyOnSelect).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(
                    title: "Scrollback limit",
                    detail: "Memory reserved per pane for scrollback output history"
                ) {
                    ChoicePopUp(label: "Scrollback limit", options: scrollbackLimitOptions, selection: scrollbackLimitSelection)
                }
            }

            SettingsGroup(title: "Shell and closing") {
                SettingsTabRow(
                    title: "Pin Zsh prompt to bottom",
                    detail: "Keeps new interactive prompts at the bottom row without changing dotfiles",
                    first: true
                ) {
                    Toggle("Pin Zsh prompt to bottom", isOn: $pinPromptToBottom).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(
                    title: "Confirm before closing running commands",
                    detail: "Asks before closing a tab, split, or drawer with an active process"
                ) {
                    Toggle("Confirm before closing running commands", isOn: $confirmCloseRunningProcess)
                        .labelsHidden().toggleStyle(.switch)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            fontSizeOverride = AppPreferences().value(Preference.terminalFontSize)
        }
    }

    private func resetTerminalSettings() {
        AppPreferences().reset(.terminal)
        fontSizeOverride = nil
    }
}

/// Live preview of the terminal surface inside Settings > Terminal reflecting theme, ANSI colors, padding, typography and cursor style.
private struct TerminalSettingsPreview: View {
    let profile: TerminalAppearanceProfile
    let pinPromptToBottom: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var previewMonospace: MonospaceSettings {
        MonospaceSettings(
            family: profile.fontFamily ?? MonospaceSettings.systemFamily,
            size: CGFloat(profile.fontSize),
            ligatures: profile.ligatures
        )
    }

    private var previewFont: Font {
        Font(previewMonospace.font(MonospaceSettings.defaultSize, weight: .regular))
    }

    private var previewBoldFont: Font {
        Font(previewMonospace.font(MonospaceSettings.defaultSize, weight: .bold))
    }

    private func paletteColor(_ index: Int, fallback: RGBA) -> Color {
        guard profile.palette.indices.contains(index) else {
            return Color(profile.adjustedForMinimumContrast(fallback))
        }
        return Color(profile.adjustedForMinimumContrast(profile.palette[index]))
    }

    private func rawPaletteColor(_ index: Int, fallback: RGBA) -> Color {
        guard profile.palette.indices.contains(index) else { return Color(fallback) }
        return Color(profile.palette[index])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("~/carrier")
                    .font(previewBoldFont)
                    .foregroundStyle(paletteColor(6, fallback: profile.foreground))
                Text("feat/terminal-ui")
                    .font(previewFont)
                    .foregroundStyle(paletteColor(5, fallback: profile.foreground))
                Text("❯")
                    .font(previewBoldFont)
                    .foregroundStyle(Color(profile.cursorColor))
                Text("pnpm test && git status")
                    .font(previewFont)
                    .foregroundStyle(Color(profile.foreground))
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                Text("✓ PASS")
                    .font(previewBoldFont)
                    .foregroundStyle(paletteColor(2, fallback: profile.boldColor))
                Text("1609")
                    .font(previewBoldFont)
                    .foregroundStyle(Color(profile.boldColor))
                Text("tests")
                    .font(previewFont)
                    .foregroundStyle(Color(profile.foreground))
                Text("· dim contrast sample")
                    .font(previewFont)
                    .foregroundStyle(paletteColor(8, fallback: profile.foreground))
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                Text("WARN")
                    .font(previewBoldFont)
                    .foregroundStyle(paletteColor(3, fallback: profile.foreground))
                Text("ERR")
                    .font(previewBoldFont)
                    .foregroundStyle(paletteColor(1, fallback: profile.foreground))
                Text("a != b => c")
                    .font(previewFont)
                    .foregroundStyle(paletteColor(4, fallback: profile.foreground))
                Text("selected text")
                    .font(previewFont)
                    .foregroundStyle(Color(profile.selectionForeground))
                    .padding(.horizontal, 4)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color(profile.selectionBackground)))
            }

            HStack(spacing: 3) {
                ForEach(0..<16, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(rawPaletteColor(index, fallback: profile.foreground))
                        .frame(width: 12, height: 6)
                }
                Spacer(minLength: 6)
                Text("ANSI 0–15")
                    .font(previewFont)
                    .foregroundStyle(paletteColor(8, fallback: profile.foreground))
            }
            .padding(.top, 2)

            if pinPromptToBottom {
                Spacer(minLength: 6)
            }

            HStack(spacing: 6) {
                Text("~/carrier")
                    .font(previewBoldFont)
                    .foregroundStyle(paletteColor(6, fallback: profile.foreground))
                Text("❯")
                    .font(previewBoldFont)
                    .foregroundStyle(Color(profile.cursorColor))
                HStack(spacing: 0) {
                    Text("cargo test --lib ")
                        .font(previewFont)
                        .foregroundStyle(Color(profile.foreground))
                    cursorGlyph
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 164, alignment: pinPromptToBottom ? .bottomLeading : .topLeading)
        .padding(.horizontal, CGFloat(profile.paddingX))
        .padding(.vertical, CGFloat(profile.paddingY))
        .background {
            if profile.isSurfaceTranslucent {
                ZStack {
                    Rectangle().fill(.regularMaterial)
                    Rectangle().fill(Color(profile.chromeBackground))
                }
            } else {
                Rectangle().fill(Color(profile.background))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var cursorGlyph: some View {
        if profile.cursorBlink && reduceMotion == false {
            TimelineView(.periodic(from: .now, by: 0.55)) { context in
                let visible = Int(context.date.timeIntervalSinceReferenceDate / 0.55).isMultiple(of: 2)
                cursorShape
                    .opacity(visible ? 1 : 0.12)
                    .animation(.easeInOut(duration: 0.12), value: visible)
            }
        } else {
            cursorShape
        }
    }

    @ViewBuilder
    private var cursorShape: some View {
        switch profile.cursorStyle {
        case .block:
            Text(" ")
                .font(previewFont)
                .foregroundStyle(Color(profile.cursorText))
                .background(Rectangle().fill(Color(profile.cursorColor)))
        case .bar:
            Text(" ")
                .font(previewFont)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color(profile.cursorColor))
                        .frame(width: 2)
                }
        case .underline:
            Text(" ")
                .font(previewFont)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color(profile.cursorColor))
                        .frame(height: 2)
                }
        }
    }
}
