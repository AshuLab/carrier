import CarrierCore
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
    private var statesPreview: some View {
        SettingsPreview {
            // together in the middle, not one to a quarter of the width
            HStack(alignment: .top, spacing: Tokens.Space.none) {
                state("Working") { StateGlyph(state: .running) }
                state("Needs attention") { StateGlyph(state: .needsYou, attention: .input) }
                state("Ready for test") { StateGlyph(state: .ready) }
                state("A problem") { StateGlyph(state: .needsYou, attention: .error) }
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
