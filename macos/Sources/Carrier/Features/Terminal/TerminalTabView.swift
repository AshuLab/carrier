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
        [(value: nil, title: Copy.terminalSameAsApp(theme: appTheme.title()))]
            + Theme.allCases.map { (value: $0, title: $0.title()) }
    }

    private var appFontDisplayName: String {
        TerminalSettings.cleanFontFamily(appFontFamily) ?? MonospaceSettings.systemFamily
    }

    private var fontFamilyOptions: [(value: String?, title: String)] {
        let families = TerminalSettings.availableFontFamilies(
            installed: MonospaceStyle.installedFamilies,
            currentOverride: fontFamilyOverride
        )
        return [(value: nil, title: Copy.terminalSameAsAppearance(value: appFontDisplayName))]
            + families.map { (value: $0, title: $0) }
    }

    private var fontSizeOptions: [(value: Int?, title: String)] {
        let sizes = TerminalSettings.availableFontSizes(currentOverride: fontSizeOverride)
        return [(value: nil, title: Copy.terminalSameAsAppearance(value: Copy.terminalPoints(size: Int(appFontSize.rounded()))))]
            + sizes.map { (value: $0, title: Copy.terminalPoints(size: $0)) }
    }

    private var ligaturesOptions: [(value: Bool?, title: String)] {
        [
            (value: nil, title: Copy.terminalSameAsAppearance(value: appLigatures ? Copy.terminalOn() : Copy.terminalOff())),
            (value: true, title: Copy.terminalOn()),
            (value: false, title: Copy.terminalOff()),
        ]
    }

    private var cursorStyleOptions: [(value: TerminalCursorStyleChoice, title: String, icon: AppIcon?)] {
        TerminalCursorStyleChoice.allCases.map { (value: $0, title: $0.title(), icon: nil) }
    }

    private var optionAsAltOptions: [(value: TerminalOptionAsAlt, title: String)] {
        TerminalOptionAsAlt.allCases.map { (value: $0, title: $0.title()) }
    }

    private var scrollbackLimitOptions: [(value: TerminalScrollbackLimit, title: String)] {
        TerminalScrollbackLimit.allCases.map { (value: $0, title: $0.title()) }
    }

    var body: some View {
        SettingsPageBody(reset: resetTerminalSettings) {
            SettingsGroup(id: "appearance", title: Copy.terminalSettingsAppearance()) {
                SettingsTabRow(id: "theme", title: Copy.terminalSettingsTheme(), detail: Copy.terminalSettingsThemeDetail(), first: true) {
                    ChoicePopUp(label: Copy.terminalSettingsTheme(), options: themeOptions, selection: $themeOverride)
                }
                SettingsTabRow(
                    id: "minimum-contrast", title: Copy.terminalSettingsContrast(),
                    detail: Copy.terminalSettingsContrastDetail(contrast: TerminalSettings.minimumContrastLabel(minimumContrast))
                ) {
                    Slider(value: minimumContrastSelection, in: TerminalSettings.minimumContrastRange)
                        .labelsHidden().frame(width: settingsSliderWidth)
                        .accessibilityLabel(Copy.terminalSettingsContrast())
                        .accessibilityValue(TerminalSettings.minimumContrastLabel(minimumContrast))
                }
                SettingsTabRow(
                    id: "horizontal-padding", title: Copy.terminalSettingsPaddingX(),
                    detail: Copy.terminalSettingsPaddingXDetail(size: Int(paddingX.rounded()))
                ) {
                    Slider(value: paddingXSelection, in: TerminalSettings.paddingRange)
                        .labelsHidden().frame(width: settingsSliderWidth)
                        .accessibilityLabel(Copy.terminalSettingsPaddingX())
                        .accessibilityValue(Copy.terminalPointsValue(count: Int(paddingX.rounded())))
                }
                SettingsTabRow(
                    id: "vertical-padding", title: Copy.terminalSettingsPaddingY(),
                    detail: Copy.terminalSettingsPaddingYDetail(size: Int(paddingY.rounded()))
                ) {
                    Slider(value: paddingYSelection, in: TerminalSettings.paddingRange)
                        .labelsHidden().frame(width: settingsSliderWidth)
                        .accessibilityLabel(Copy.terminalSettingsPaddingY())
                        .accessibilityValue(Copy.terminalPointsValue(count: Int(paddingY.rounded())))
                }
                SettingsPreview {
                    TerminalSettingsPreview(profile: previewProfile, pinPromptToBottom: pinPromptToBottom)
                }
            }

            SettingsGroup(id: "typography", title: Copy.terminalSettingsTypography()) {
                SettingsTabRow(
                    id: "font", title: Copy.terminalSettingsFont(),
                    detail: Copy.terminalSettingsFontDetail(),
                    first: true
                ) {
                    ChoicePopUp(label: Copy.terminalSettingsFont(), options: fontFamilyOptions, selection: fontFamilySelection)
                }
                SettingsTabRow(id: "size", title: Copy.terminalSettingsSize(), detail: Copy.terminalSettingsSizeDetail()) {
                    ChoicePopUp(label: Copy.terminalSettingsSize(), options: fontSizeOptions, selection: fontSizeSelection)
                }
                SettingsTabRow(id: "ligatures", title: Copy.terminalSettingsLigatures(), detail: Copy.terminalSettingsLigaturesDetail()) {
                    ChoicePopUp(label: Copy.terminalSettingsLigatures(), options: ligaturesOptions, selection: $fontLigaturesOverride)
                }
                SettingsTabRow(id: "thicken-font", title: Copy.terminalSettingsThicken(), detail: Copy.terminalSettingsThickenDetail()) {
                    Toggle(Copy.terminalSettingsThicken(), isOn: $fontThicken).labelsHidden().toggleStyle(.switch)
                }
            }

            SettingsGroup(id: "cursor", title: Copy.terminalSettingsCursor()) {
                SettingsTabRow(id: "cursor-style", title: Copy.terminalSettingsCursorStyle(), detail: Copy.terminalSettingsCursorStyleDetail(), first: true) {
                    SegmentedChoice(options: cursorStyleOptions, selection: $cursorStyle)
                }
                SettingsTabRow(id: "blink-cursor", title: Copy.terminalSettingsBlink(), detail: Copy.terminalSettingsBlinkDetail()) {
                    Toggle(Copy.terminalSettingsBlink(), isOn: $cursorBlink).labelsHidden().toggleStyle(.switch)
                }
            }

            SettingsGroup(id: "panes", title: Copy.terminalSettingsPanes()) {
                SettingsTabRow(
                    id: "dim-inactive-panes", title: Copy.terminalSettingsDim(),
                    detail: Copy.terminalSettingsDimDetail(),
                    first: true
                ) {
                    Toggle(Copy.terminalSettingsDim(), isOn: $dimInactivePanes).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(
                    id: "focus-follows-mouse", title: Copy.terminalSettingsFocusFollows(),
                    detail: Copy.terminalSettingsFocusFollowsDetail()
                ) {
                    Toggle(Copy.terminalSettingsFocusFollows(), isOn: $focusFollowsMouse).labelsHidden().toggleStyle(.switch)
                }
            }

            SettingsGroup(id: "input-and-scrollback", title: Copy.terminalSettingsInput()) {
                SettingsTabRow(
                    id: "option-as-alt", title: Copy.terminalSettingsOptionAsAlt(),
                    detail: Copy.terminalSettingsOptionAsAltDetail(),
                    first: true
                ) {
                    ChoicePopUp(label: Copy.terminalSettingsOptionAsAlt(), options: optionAsAltOptions, selection: $optionAsAlt)
                }
                SettingsTabRow(
                    id: "copy-on-select", title: Copy.terminalSettingsCopyOnSelect(),
                    detail: Copy.terminalSettingsCopyOnSelectDetail()
                ) {
                    Toggle(Copy.terminalSettingsCopyOnSelect(), isOn: $copyOnSelect).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(
                    id: "scrollback-limit", title: Copy.terminalSettingsScrollback(),
                    detail: Copy.terminalSettingsScrollbackDetail()
                ) {
                    ChoicePopUp(label: Copy.terminalSettingsScrollback(), options: scrollbackLimitOptions, selection: scrollbackLimitSelection)
                }
            }

            SettingsGroup(id: "shell-and-closing", title: Copy.terminalSettingsShell()) {
                SettingsTabRow(
                    id: "pin-zsh-prompt-to-bottom", title: Copy.terminalSettingsPinPrompt(),
                    detail: Copy.terminalSettingsPinPromptDetail(),
                    first: true
                ) {
                    Toggle(Copy.terminalSettingsPinPrompt(), isOn: $pinPromptToBottom).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(
                    id: "confirm-before-closing-running-commands", title: Copy.terminalSettingsConfirm(),
                    detail: Copy.terminalSettingsConfirmDetail()
                ) {
                    Toggle(Copy.terminalSettingsConfirm(), isOn: $confirmCloseRunningProcess)
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
