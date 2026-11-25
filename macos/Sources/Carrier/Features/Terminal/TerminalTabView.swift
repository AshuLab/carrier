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
            SettingsGroup(id: "appearance", title: "Appearance") {
                SettingsTabRow(id: "theme", title: "Theme", detail: "Color palette for panes; inherits the app theme by default", first: true) {
                    ChoicePopUp(label: "Theme", options: themeOptions, selection: $themeOverride)
                }
                SettingsTabRow(
                    id: "minimum-contrast", title: "Minimum contrast",
                    detail: "Raises low-contrast ANSI text · \(TerminalSettings.minimumContrastLabel(minimumContrast))"
                ) {
                    Slider(value: minimumContrastSelection, in: TerminalSettings.minimumContrastRange)
                        .labelsHidden().frame(width: settingsSliderWidth)
                        .accessibilityLabel("Minimum contrast")
                        .accessibilityValue(TerminalSettings.minimumContrastLabel(minimumContrast))
                }
                SettingsTabRow(
                    id: "horizontal-padding", title: "Horizontal padding",
                    detail: "Left and right margin inside each pane · \(Int(paddingX.rounded())) pt"
                ) {
                    Slider(value: paddingXSelection, in: TerminalSettings.paddingRange)
                        .labelsHidden().frame(width: settingsSliderWidth)
                        .accessibilityLabel("Horizontal padding")
                        .accessibilityValue("\(Int(paddingX.rounded())) points")
                }
                SettingsTabRow(
                    id: "vertical-padding", title: "Vertical padding",
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

            SettingsGroup(id: "typography", title: "Typography") {
                SettingsTabRow(
                    id: "font", title: "Font",
                    detail: "Monospaced font used in panes; inherits Appearance › Code and output",
                    first: true
                ) {
                    ChoicePopUp(label: "Font", options: fontFamilyOptions, selection: fontFamilySelection)
                }
                SettingsTabRow(id: "size", title: "Size", detail: "Text size in points for terminal output") {
                    ChoicePopUp(label: "Size", options: fontSizeOptions, selection: fontSizeSelection)
                }
                SettingsTabRow(id: "ligatures", title: "Ligatures", detail: "Joins pairs such as != and >= where the font has them") {
                    ChoicePopUp(label: "Ligatures", options: ligaturesOptions, selection: $fontLigaturesOverride)
                }
                SettingsTabRow(id: "thicken-font", title: "Thicken font", detail: "Renders glyphs slightly heavier on Retina displays") {
                    Toggle("Thicken font", isOn: $fontThicken).labelsHidden().toggleStyle(.switch)
                }
            }

            SettingsGroup(id: "cursor", title: "Cursor") {
                SettingsTabRow(id: "cursor-style", title: "Cursor style", detail: "Shape of the text cursor inside terminal panes", first: true) {
                    SegmentedChoice(options: cursorStyleOptions, selection: $cursorStyle)
                }
                SettingsTabRow(id: "blink-cursor", title: "Blink cursor", detail: "Animates the cursor when the pane is focused") {
                    Toggle("Blink cursor", isOn: $cursorBlink).labelsHidden().toggleStyle(.switch)
                }
            }

            SettingsGroup(id: "panes", title: "Panes") {
                SettingsTabRow(
                    id: "dim-inactive-panes", title: "Dim inactive panes",
                    detail: "Softens unfocused split panes so the active pane stands out",
                    first: true
                ) {
                    Toggle("Dim inactive panes", isOn: $dimInactivePanes).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(
                    id: "focus-follows-mouse", title: "Focus follows mouse",
                    detail: "Activates split panes when hovering over them without clicking"
                ) {
                    Toggle("Focus follows mouse", isOn: $focusFollowsMouse).labelsHidden().toggleStyle(.switch)
                }
            }

            SettingsGroup(id: "input-and-scrollback", title: "Input and scrollback") {
                SettingsTabRow(
                    id: "option-as-alt", title: "Option as Alt",
                    detail: "Sends Option key presses as Meta/Alt escape sequences in shells",
                    first: true
                ) {
                    ChoicePopUp(label: "Option as Alt", options: optionAsAltOptions, selection: $optionAsAlt)
                }
                SettingsTabRow(
                    id: "copy-on-select", title: "Copy on select",
                    detail: "Copies highlighted terminal text to the clipboard automatically"
                ) {
                    Toggle("Copy on select", isOn: $copyOnSelect).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(
                    id: "scrollback-limit", title: "Scrollback limit",
                    detail: "Memory reserved per pane for scrollback output history"
                ) {
                    ChoicePopUp(label: "Scrollback limit", options: scrollbackLimitOptions, selection: scrollbackLimitSelection)
                }
            }

            SettingsGroup(id: "shell-and-closing", title: "Shell and closing") {
                SettingsTabRow(
                    id: "pin-zsh-prompt-to-bottom", title: "Pin Zsh prompt to bottom",
                    detail: "Keeps new interactive prompts at the bottom row without changing dotfiles",
                    first: true
                ) {
                    Toggle("Pin Zsh prompt to bottom", isOn: $pinPromptToBottom).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(
                    id: "confirm-before-closing-running-commands", title: "Confirm before closing running commands",
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
