import CarrierCore
import CarrierUI
import SwiftUI

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
            FlowLayout(spacing: Tokens.Space.s22) {
                ForEach([AppIcon.search, .settings, .folder, .copy, .bell, .trash, .refresh, .lock, .microphone, .terminal], id: \.self) { Glyph($0, size: 22) }
            }
            .foregroundStyle(.primary).frame(maxWidth: .infinity)
        }
    }

    @AppStorage(Preference.appearanceStatesByShape) private var statesByShape
    /// The four states as the app draws them now, with or without their symbols, larger than they are in a row so the mark inside reads.
    private func statesPreview(_ page: AppearancePage) -> some View {
        SettingsPreview {
            // together in the middle, not one to a quarter of the width
            HStack(alignment: .top, spacing: Tokens.Space.none) {
                state(page.stateWorking) { StateGlyph(state: .running) }
                state(page.stateNeedsAttention) { StateGlyph(state: .needsYou, attention: .input) }
                state(page.stateReady) { StateGlyph(state: .ready) }
                state(page.stateProblem) { StateGlyph(state: .needsYou, attention: .error) }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func state(_ title: String, @ViewBuilder glyph: () -> some View) -> some View {
        VStack(spacing: Tokens.Space.s8) {
            // at its own size: scaling the 20-point glyph up scaled its pixels, and the ring (a layer) showed them
            glyph().frame(width: 28, height: 28)
            Text(title).scaledFont(12).foregroundStyle(.secondary)
        }
        .frame(width: 120)
    }

    var body: some View {
        let page = appearancePage(textSize: textSize, iconWeight: iconWeight, codeSize: Int(codeSize))
        SettingsPageBody(reset: { AppPreferences().reset(.appearance) }) {
            SettingsGroup(id: "theme", title: page.theme) {
                ThemeGallery(theme: $theme)
            }
            SettingsGroup(id: "look", title: page.look) {
                SettingsTabRow(id: "color-scheme", title: page.colorScheme.title, detail: page.colorScheme.detail, first: true) {
                    ChoicePopUp(label: page.colorScheme.title, options: ColorSchemeChoice.allCases.map { (value: $0, title: $0.title()) }, selection: $colorScheme)
                }
                SettingsTabRow(id: "text-size", title: page.textSize.title, detail: page.textSize.detail) {
                    Slider(
                        value: Binding(get: { Double(textSize) }, set: { textSize = Int($0) }),
                        in: Double(TypeScale.range.lowerBound)...Double(TypeScale.range.upperBound), step: 5
                    )
                    .labelsHidden().frame(width: settingsSliderWidth).accessibilityLabel(page.textSize.title).accessibilityValue(page.textSizeValue)
                }
                SettingsTabRow(id: "icon-set", title: page.iconSet.title, detail: page.iconSet.detail) {
                    ChoicePopUp(
                        label: page.iconSet.title, options: IconSet.allCases.map { (value: $0, title: $0.title()) },
                        selection: $iconSet
                    )
                }
                SettingsTabRow(id: "icon-weight", title: page.iconWeight.title, detail: page.iconWeight.detail) {
                    Slider(value: $iconWeight, in: IconWeight.range, step: IconWeight.step)
                        .labelsHidden().frame(width: settingsSliderWidth)
                        .accessibilityLabel(page.iconWeight.title).accessibilityValue(page.iconWeightValue)
                }
                iconsPreview
                SettingsTabRow(id: "density", title: page.density.title, detail: page.density.detail) {
                    ChoicePopUp(label: page.density.title, options: Density.allCases.map { (value: $0, title: $0.title()) }, selection: $density)
                }
                SettingsTabRow(id: "tell-states-apart-by-shape", title: page.byShape.title, detail: page.byShape.detail) {
                    Toggle(page.byShape.title, isOn: $statesByShape).labelsHidden().toggleStyle(.switch)
                }
                statesPreview(page)
            }
            SettingsGroup(id: "color", title: page.color) {
                SettingsTabRow(id: "accent-color", title: page.accent.title, detail: page.accent.detail, first: true) {
                    AccentSwatches(theme: theme, scheme: scheme == .dark ? .dark : .light, accent: accent)
                }
                SettingsTabRow(id: "tint-the-windows", title: page.tint.title, detail: page.tint.detail) {
                    ChoicePopUp(label: page.tint.title, options: Tint.allCases.map { (value: $0, title: $0.title()) }, selection: $tint)
                }
                SettingsTabRow(id: "translucent-windows", title: page.translucent.title, detail: page.translucent.detail) {
                    Toggle(page.translucent.title, isOn: Binding(
                        get: { translucentChoice ?? (reduceTransparency == false) }, set: { translucentChoice = $0 }
                    ))
                    .labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsGroup(id: "code-and-output", title: page.code) {
                SettingsTabRow(id: "font", title: page.font.title, detail: page.font.detail, first: true) {
                    // a family that is no longer installed shows as the system's, as the views draw it
                    ChoicePopUp(
                        label: page.font.title, options: ([MonospaceSettings.systemFamily] + MonospaceStyle.installedFamilies).map { (value: $0, title: $0) },
                        selection: Binding(
                            get: { MonospaceStyle.installedFamilies.contains(family) ? family : MonospaceSettings.systemFamily },
                            set: { family = $0 }
                        )
                    )
                }
                SettingsTabRow(id: "size", title: page.size.title, detail: page.size.detail) {
                    Slider(value: $codeSize, in: Double(MonospaceSettings.sizeRange.lowerBound)...Double(MonospaceSettings.sizeRange.upperBound), step: 1)
                        .labelsHidden().frame(width: settingsSliderWidth).accessibilityLabel(page.codeSize).accessibilityValue(page.codeSizeValue)
                }
                SettingsTabRow(id: "line-height", title: page.lineHeight.title, detail: page.lineHeight.detail) {
                    ChoicePopUp(label: page.lineHeight.title, options: LineHeight.allCases.map { (value: $0, title: $0.title()) }, selection: $lineHeight)
                }
                SettingsTabRow(id: "ligatures", title: page.ligatures.title, detail: page.ligatures.detail) {
                    Toggle(page.ligatures.title, isOn: $ligatures).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "wrap-long-lines", title: page.wrap.title, detail: page.wrap.detail) {
                    Toggle(page.wrap.title, isOn: $wrapLongLines).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "line-numbers", title: page.lineNumbers.title, detail: page.lineNumbers.detail) {
                    Toggle(page.lineNumbers.title, isOn: $lineNumbers).labelsHidden().toggleStyle(.switch)
                }
                codePreview()
            }
        }
    }
}
