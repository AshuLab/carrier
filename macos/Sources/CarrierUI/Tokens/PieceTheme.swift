import AppKit
import CarrierCore
import Observation
import SwiftUI

/// What a piece reads from the app beyond `.tint` and the text size, set at the root of each window (`themed()`): the surfaces of the theme, and the set and
/// weight of the outline icons. It grows only with what the pieces really read.
/// `accent` is the same color `.tint` carries, for a piece that has to mix it with black or white, which a `ShapeStyle` cannot do.
struct PieceTheme: Equatable, Sendable {
    var surfaces: ThemeSurfaces
    var iconWeight: Double
    var iconSet: IconSet
    /// Whether a state is told apart by its shape and not by its color alone (Settings > Appearance): the state pieces draw its symbol.
    var statesByShape = false

    /// What a view outside any window of the app (a preview) reads: the default theme, in light.
    static let standard = PieceTheme(
        surfaces: themeSurfaces(.carrier, scheme: .light, translucent: false), iconWeight: IconWeight.defaultWeight, iconSet: IconSet.defaultSet)

    var accent: Color { surfaces.accent.map(Color.init) ?? .accentColor }

    /// The accent a main action is tinted with on glass (the New session pill, the message box's send button): darkened, so white reads on it and it is not as loud as the system's prominent button.
    var accentGlass: Color { accent.mix(with: .black, by: 0.4) }

    /// The fill of the selected row of a sidebar list. On dark the accent is deepened, so the white words keep their contrast and it is not as
    /// loud as the accent itself; on light the accent at 45 % behind the dark words is already quiet.
    func selectedRow(dark: Bool) -> Color { dark ? accent.mix(with: .black, by: 0.5).opacity(0.85) : accent.opacity(0.45) }

    /// The accent as text on its own tinted piece (the chosen filter, the chosen segment): a little lifted in the dark and deepened in the light, so it keeps its contrast.
    func accentInk(_ scheme: ColorScheme) -> Color { accent.mix(with: scheme == .dark ? .white : .black, by: scheme == .dark ? 0.3 : 0.2) }
}

extension EnvironmentValues {
    /// The person's text size, for `scaledFont` and the pieces that size things by it.
    @Entry var textScale = TypeScale()
    @Entry var pieceTheme = PieceTheme.standard
}

/// The icon set and the weight of the outline icons the person chose, and whether states are told apart by shape, for the roots of the windows to read while
/// they draw: moving the slider or choosing another set in Appearance redraws every icon at once (the same way `TextSize` does for the text). Non-view code
/// that draws an icon reads it here too.
@Observable final class IconAppearance {
    static let shared = IconAppearance()

    private(set) var set = IconSet.stored()
    private(set) var weight = IconWeight.stored()
    private(set) var statesByShape = AppPreferences().statesByShape

    private init() {
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [self] _ in
            let stored = IconSet.stored()
            if stored != set { set = stored }
            let storedWeight = IconWeight.stored()
            if storedWeight != weight { weight = storedWeight }
            let storedByShape = AppPreferences().statesByShape
            if storedByShape != statesByShape { statesByShape = storedByShape }
        }
    }
}

/// The text size and the `PieceTheme` the person chose, on the environment below. Read in its own body, while the view draws, so a change reaches every
/// piece under it, whatever window it is in.
struct PieceEnvironment: ViewModifier {
    func body(content: Content) -> some View {
        let icons = IconAppearance.shared
        content
            .environment(\.textScale, TextSize.shared.scale)
            .environment(\.pieceTheme, PieceTheme(surfaces: AppTheme.shared.surfaces, iconWeight: icons.weight, iconSet: icons.set, statesByShape: icons.statesByShape))
    }
}

extension IconImages {
    /// For the AppKit that draws an icon itself (an attachment, a layer): the icon in the set and at the weight now, with `bold` as `Glyph` has it. An SF
    /// Symbol comes at `pointSize` and the weight as the weight of its font, as `Glyph` draws it.
    static func image(_ icon: AppIcon, bold: Bool = false, pointSize: CGFloat = 24) -> NSImage {
        let style = IconAppearance.shared
        return image(icon, set: style.set, weight: style.weight, bold: bold, pointSize: pointSize)
    }
}

extension Image {
    /// An icon of the interface to put inside a `Text` (`Text("\(Image(inline: .gitBranch)) main")`), where a view cannot go: sized in points to the text, in
    /// the set and weight now, and a template, so it takes the color of the text.
    @MainActor init(inline icon: AppIcon, size: CGFloat = 11) {
        let style = IconAppearance.shared
        self.init(nsImage: IconImages.inline(icon, side: TextSize.shared.scale.size(size), set: style.set, weight: style.weight))
    }
}
