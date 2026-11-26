import Foundation

/// Complete high-contrast appearance & typography profile fed into Ghostty's `TerminalConfiguration`.
public struct TerminalAppearanceProfile: Equatable, Sendable {
    public let theme: Theme
    public let scheme: ThemeScheme
    public let accent: AccentColor?
    public let tint: Tint
    public let translucent: Bool
    public let isSurfaceTranslucent: Bool
    /// Solid effective RGB background used by Ghostty for contrast calculations and subpixel blending.
    public let background: RGBA
    /// Window surface color matching `themeSurfaces(..., translucent: translucent)` for SwiftUI chrome behind/around panes.
    public let chromeBackground: RGBA
    public let backgroundOpacity: Double
    public let foreground: RGBA
    public let boldColor: RGBA
    public let selectionBackground: RGBA
    public let selectionForeground: RGBA
    public let cursorColor: RGBA
    public let cursorText: RGBA
    /// 16-color ANSI palette (0...15) tailored for the active Carrier theme and light/dark scheme.
    public let palette: [RGBA]
    public let fontFamily: String?
    public let fontSize: Double
    public let ligatures: Bool
    public let fontThicken: Bool
    public let cursorStyle: TerminalCursorStyleChoice
    public let cursorBlink: Bool
    public let paddingX: Double
    public let paddingY: Double
    public let minimumContrast: Double
    public let dimInactivePanes: Bool
    public let focusFollowsMouse: Bool
    public let optionAsAlt: TerminalOptionAsAlt
    public let copyOnSelect: Bool
    public let scrollbackLimit: TerminalScrollbackLimit

    public init(
        theme: Theme,
        scheme: ThemeScheme = .dark,
        accent: AccentColor? = nil,
        tint: Tint = .off,
        translucent: Bool = false,
        monospace: MonospaceSettings = MonospaceSettings(),
        terminalSettings: TerminalSettings = TerminalSettings()
    ) {
        let resolvedTheme = terminalSettings.effectiveTheme(appTheme: theme)
        let solidSurfaces = themeSurfaces(resolvedTheme, scheme: scheme, accent: accent, tint: tint, translucent: false)
        let chromeSurfaces = themeSurfaces(resolvedTheme, scheme: scheme, accent: accent, tint: tint, translucent: translucent)
        let background = solidSurfaces.window
        let resolvedAccent = solidSurfaces.accent ?? RGBA(hex: scheme == .dark ? 0x0a84ff : 0x0066cc)
        // the surface is glass for every theme: the terminal draws no background and the card behind it is the theme's color over glass
        let isSurfaceTranslucent = translucent

        let preferredInk = RGBA(hex: scheme == .dark ? 0xf2f4f8 : 0x15171c)
        let fallbackDark = RGBA(hex: 0x0a0b0e)
        let fallbackLight = RGBA(hex: 0xffffff)
        let bestInk: RGBA
        if preferredInk.contrastRatio(with: background) >= 7.0 {
            bestInk = preferredInk
        } else {
            bestInk = fallbackLight.contrastRatio(with: background) >= fallbackDark.contrastRatio(with: background)
                ? fallbackLight
                : fallbackDark
        }

        let preferredBold = scheme == .dark ? fallbackLight : fallbackDark
        let boldColor = preferredBold.contrastRatio(with: background) >= bestInk.contrastRatio(with: background)
            ? preferredBold
            : bestInk

        let selectionAlpha = scheme == .dark ? 0.34 : 0.24
        let selectionBackground = background.covered(
            by: RGBA(red: resolvedAccent.red, green: resolvedAccent.green, blue: resolvedAccent.blue, alpha: selectionAlpha)
        )
        let selectionForeground: RGBA
        if bestInk.contrastRatio(with: selectionBackground) >= 6.5 {
            selectionForeground = bestInk
        } else {
            selectionForeground = fallbackLight.contrastRatio(with: selectionBackground) >= fallbackDark.contrastRatio(with: selectionBackground)
                ? fallbackLight
                : fallbackDark
        }

        var cursorColor = resolvedAccent
        if cursorColor.contrastRatio(with: background) < 3.5 {
            for step in 1...10 {
                let candidate = resolvedAccent.blended(toward: bestInk, fraction: Double(step) * 0.1)
                cursorColor = candidate
                if candidate.contrastRatio(with: background) >= 3.5 { break }
            }
        }
        let pureBlack = RGBA(hex: 0x000000)
        let cursorText = fallbackLight.contrastRatio(with: cursorColor) >= pureBlack.contrastRatio(with: cursorColor)
            ? fallbackLight
            : pureBlack

        self.theme = resolvedTheme
        self.scheme = scheme
        self.accent = accent
        self.tint = tint
        self.translucent = translucent
        self.isSurfaceTranslucent = isSurfaceTranslucent
        self.background = background
        self.chromeBackground = chromeSurfaces.window
        self.backgroundOpacity = isSurfaceTranslucent ? 0.0 : 1.0
        self.foreground = bestInk
        self.boldColor = boldColor
        self.selectionBackground = selectionBackground
        self.selectionForeground = selectionForeground
        self.cursorColor = cursorColor
        self.cursorText = cursorText
        self.palette = themeTerminalPalette(for: resolvedTheme, scheme: scheme)
        self.fontFamily = terminalSettings.effectiveFontFamily(appMonospace: monospace)
        self.fontSize = terminalSettings.effectiveFontSize(appMonospace: monospace)
        self.ligatures = terminalSettings.effectiveLigatures(appMonospace: monospace)
        self.fontThicken = terminalSettings.fontThicken
        self.cursorStyle = terminalSettings.cursorStyle
        self.cursorBlink = terminalSettings.cursorBlink
        self.paddingX = terminalSettings.paddingX
        self.paddingY = terminalSettings.paddingY
        self.minimumContrast = terminalSettings.minimumContrast
        self.dimInactivePanes = terminalSettings.dimInactivePanes
        self.focusFollowsMouse = terminalSettings.focusFollowsMouse
        self.optionAsAlt = terminalSettings.optionAsAlt
        self.copyOnSelect = terminalSettings.copyOnSelect
        self.scrollbackLimit = terminalSettings.scrollbackLimit
    }

    /// Adjusts a terminal foreground color toward `foreground` until it meets `minimumContrast` against `background`.
    public func adjustedForMinimumContrast(_ color: RGBA) -> RGBA {
        guard minimumContrast > 1.0 else { return color }
        if color.contrastRatio(with: background) >= minimumContrast {
            return color
        }
        var adjusted = color
        for step in 1...20 {
            let candidate = color.blended(toward: foreground, fraction: Double(step) * 0.05)
            adjusted = candidate
            if candidate.contrastRatio(with: background) >= minimumContrast {
                break
            }
        }
        return adjusted
    }
}

private func hexPalette(_ hexValues: [UInt32]) -> [RGBA] {
    hexValues.map { RGBA(hex: $0) }
}

/// Curated 16-color ANSI palettes (0...7 normal, 8...15 bright) harmonized with each of Carrier's 20 themes in both light and dark modes.
private func themeTerminalPalette(for theme: Theme, scheme: ThemeScheme) -> [RGBA] {
    switch (theme, scheme) {
    case (.carrier, .dark):
        return hexPalette([
            0x161618, 0xff6961, 0x32d74b, 0xffd60a, 0x409cff, 0xda8fff, 0x64d2ff, 0xd8dae0,
            0x787880, 0xff8a80, 0x5de66f, 0xffe34d, 0x70b8ff, 0xe6b3ff, 0x90e0ff, 0xf5f5f7,
        ])
    case (.carrier, .light):
        return hexPalette([
            0x1c1c1e, 0xb82222, 0x166e30, 0x7d4f00, 0x0054b0, 0x7c1e96, 0x006388, 0xd1d1d6,
            0x55555c, 0xc72929, 0x1a7d37, 0x8c5900, 0x005fc7, 0x8f24ab, 0x00719c, 0xffffff,
        ])
    case (.graphite, .dark):
        return hexPalette([
            0x121315, 0xf07178, 0x6cc67d, 0xe5c07b, 0x7aa2d8, 0xc28be8, 0x68b7c4, 0xcaccd2,
            0x787b85, 0xf78c92, 0x8ad998, 0xf0d297, 0x98bbf0, 0xd6aaf5, 0x8ad0dc, 0xf0f1f4,
        ])
    case (.graphite, .light):
        return hexPalette([
            0x1f2023, 0xa82a30, 0x1b6634, 0x7a5410, 0x26528c, 0x6f3694, 0x145f69, 0xd4d4d8,
            0x56585f, 0xb8333a, 0x21753d, 0x8a5f13, 0x2d61a6, 0x803ea8, 0x196e78, 0xf8f8fa,
        ])
    case (.ocean, .dark):
        return hexPalette([
            0x0b141c, 0xff6e73, 0x4cd49a, 0xf2c96b, 0x32ade6, 0x9b9eff, 0x4de0dc, 0xd0e2f0,
            0x6a899e, 0xff8f94, 0x6ee6b3, 0xffd987, 0x60c6f7, 0xb8baff, 0x7ef2ee, 0xedf6fc,
        ])
    case (.ocean, .light):
        return hexPalette([
            0x112536, 0xa82532, 0x0d684a, 0x7a5200, 0x076499, 0x4e43b5, 0x00636b, 0xc8dce9,
            0x4a687d, 0xba2c3b, 0x117856, 0x8a5d00, 0x0973b0, 0x5c50cc, 0x00727c, 0xf7fbfe,
        ])
    case (.forest, .dark):
        return hexPalette([
            0x0d140f, 0xf2746b, 0x30d158, 0xd8c456, 0x5ca8e6, 0xc68ae8, 0x4fd1b5, 0xd1dfd3,
            0x6b8771, 0xff928a, 0x5ce67e, 0xebd873, 0x7ec0f5, 0xdba6f7, 0x73e6cd, 0xedf5ee,
        ])
    case (.forest, .light):
        return hexPalette([
            0x142619, 0xa82a24, 0x137330, 0x755705, 0x1b5894, 0x6f3596, 0x0d6658, 0xcce0ce,
            0x4d6b55, 0xb8322b, 0x188238, 0x856407, 0x2167ad, 0x803eab, 0x117565, 0xf7fbf7,
        ])
    case (.sunset, .dark):
        return hexPalette([
            0x17110d, 0xff6e5e, 0x7ec96b, 0xff9f0a, 0x6ba8eb, 0xe67eb8, 0x5cc4b8, 0xe6d6c8,
            0x8c7668, 0xff8f82, 0x9ad989, 0xffb84d, 0x8bc0f7, 0xf59dce, 0x7ddbd0, 0xfaf3ed,
        ])
    case (.sunset, .light):
        return hexPalette([
            0x2e1e14, 0xab2920, 0x206820, 0x874600, 0x1e5291, 0x8c2461, 0x10615c, 0xe5d3be,
            0x6b5547, 0xbd3127, 0x287828, 0x995100, 0x2561ab, 0x9e2c6f, 0x15706a, 0xfffaf5,
        ])
    case (.paper, .dark):
        return hexPalette([
            0x1a1918, 0xf0756e, 0x6fc47b, 0xe8be64, 0x6ea8ff, 0xc98be6, 0x5cc7c7, 0xdcd8d0,
            0x827e78, 0xff948e, 0x8fd699, 0xf7d281, 0x91beff, 0xdbabf2, 0x80dede, 0xf5f2eb,
        ])
    case (.paper, .light):
        return hexPalette([
            0x24221e, 0xa82924, 0x1a662e, 0x7a5004, 0x0058b5, 0x703294, 0x0e6169, 0xded9cc,
            0x615c54, 0xba312b, 0x217537, 0x8a5b06, 0x0066cf, 0x823bab, 0x137078, 0xfcfbf7,
        ])
    case (.rose, .dark):
        return hexPalette([
            0x170e12, 0xff6b9a, 0x6fd195, 0xf0be6c, 0x7baaf7, 0xe68ae0, 0x66c9d1, 0xe6d4da,
            0x8c6d79, 0xff8fb3, 0x90e3b0, 0xfad18c, 0x9cc0ff, 0xf5abef, 0x8ae0e8, 0xfaf0f4,
        ])
    case (.rose, .light):
        return hexPalette([
            0x2b171f, 0xb01e4e, 0x16683d, 0x7d4b06, 0x2352a3, 0x852380, 0x0f5f69, 0xe8cfd6,
            0x6e515c, 0xc4265b, 0x1c7848, 0x8f5708, 0x2a60bd, 0x992b93, 0x146e78, 0xfff7f9,
        ])
    case (.lavender, .dark):
        return hexPalette([
            0x120f17, 0xf2748b, 0x6ad19e, 0xebd073, 0x82aaff, 0xb58cff, 0x69d1e0, 0xdcd4eb,
            0x7e7291, 0xff94a8, 0x8ae3b7, 0xf7e092, 0xa3c2ff, 0xc9abff, 0x8ce5f2, 0xf3effb,
        ])
    case (.lavender, .light):
        return hexPalette([
            0x211930, 0xa82442, 0x146642, 0x7a5206, 0x274fad, 0x682bd6, 0x0e606e, 0xd9cff0,
            0x5e5078, 0xba2c4e, 0x1a754d, 0x8a5e08, 0x2f5ec9, 0x7938ed, 0x136f7e, 0xfaf8ff,
        ])
    case (.midnight, .dark):
        return hexPalette([
            0x070a12, 0xff6e7a, 0x4cd99c, 0xf2c864, 0x5ea3ff, 0xb88eff, 0x2dd4bf, 0xd0d8eb,
            0x697696, 0xff919b, 0x6ee8b3, 0xfad984, 0x85baff, 0xccadff, 0x5ce6d4, 0xeef2fa,
        ])
    case (.midnight, .light):
        return hexPalette([
            0x12182b, 0xa82534, 0x0e6646, 0x7a5005, 0x1d4aa3, 0x6231b0, 0x0a695b, 0xcad0e8,
            0x4e597a, 0xba2c3d, 0x137551, 0x8a5b07, 0x2458bf, 0x733cc9, 0x0e7868, 0xf7f8fc,
        ])
    case (.solarized, .dark):
        return hexPalette([
            0x073642, 0xec5e5a, 0x93a82a, 0xc99a14, 0x3b9ae0, 0xe85aa4, 0x35b0a6, 0xeee8d5,
            0x586e75, 0xf67a76, 0xa9bf3a, 0xdcae2a, 0x5cb0ee, 0xee70ae, 0x55c6bc, 0xfdf6e3,
        ])
    case (.solarized, .light):
        return hexPalette([
            0x073642, 0xc62a28, 0x5f7000, 0x8a6700, 0x1a6fb0, 0xb02a6c, 0x14756d, 0xeee8d5,
            0x586e75, 0xd13633, 0x6b7d00, 0x9a7400, 0x2078bf, 0xc03478, 0x1a8279, 0xffffff,
        ])
    case (.nord, .dark):
        return hexPalette([
            0x3b4252, 0xe08790, 0xa3be8c, 0xebcb8b, 0x8fadd0, 0xc29dbb, 0x88c0d0, 0xe5e9f0,
            0x6b7690, 0xea9ea5, 0xb5cf9f, 0xf2d9a4, 0xa8c0dc, 0xd2b4cc, 0x8fbcbb, 0xeceff4,
        ])
    case (.nord, .light):
        return hexPalette([
            0x2e3440, 0xa23d49, 0x4e7a38, 0x806010, 0x3b5f8f, 0x7e5078, 0x2f7480, 0xd8dee9,
            0x4c566a, 0xb04654, 0x588440, 0x8f6d1a, 0x4a70a2, 0x8f5e89, 0x1f7a7a, 0xffffff,
        ])
    case (.gruvbox, .dark):
        return hexPalette([
            0x3c3836, 0xfc6450, 0xb8bb26, 0xfabd2f, 0x83a598, 0xd3869b, 0x8ec07c, 0xd5c4a1,
            0x928374, 0xff8470, 0xcdd041, 0xffcf55, 0x9db8ab, 0xe0a0b0, 0xa4d391, 0xfbf1c7,
        ])
    case (.gruvbox, .light):
        return hexPalette([
            0x3c3836, 0x9d0006, 0x79740e, 0x8f5c00, 0x076678, 0x8f3f71, 0x427b58, 0xebdbb2,
            0x7c6f64, 0xb00c12, 0x6f6a0c, 0x9d6a00, 0x0d7488, 0x9d4c7e, 0x3d7550, 0xffffff,
        ])
    case (.dracula, .dark):
        return hexPalette([
            0x21222c, 0xff5555, 0x50fa7b, 0xf1fa8c, 0xbd93f9, 0xff79c6, 0x8be9fd, 0xf8f8f2,
            0x6272a4, 0xff6e6e, 0x69ff94, 0xffffa5, 0xd6acff, 0xff92df, 0xa4ffff, 0xffffff,
        ])
    case (.dracula, .light):
        return hexPalette([
            0x1f1f1f, 0xcb3a2a, 0x14710a, 0x846e15, 0x644ac9, 0xa3144d, 0x036a96, 0xcfcfde,
            0x6c664b, 0xd74c3c, 0x1f8014, 0x947d1a, 0x7459d6, 0xb81d5a, 0x0a7aa8, 0xfffbeb,
        ])
    case (.tokyoNight, .dark):
        return hexPalette([
            0x15161e, 0xf7768e, 0x9ece6a, 0xe0af68, 0x7aa2f7, 0xbb9af7, 0x7dcfff, 0xa9b1d6,
            0x414868, 0xff899d, 0x9fe044, 0xfaba4a, 0x8db0ff, 0xc7a9ff, 0xa4daff, 0xc0caf5,
        ])
    case (.tokyoNight, .light):
        return hexPalette([
            0x343b58, 0xd52558, 0x587539, 0x8b6b3d, 0x296fcf, 0x8c4dde, 0x007197, 0x6172b0,
            0xa1a6c5, 0xc73c6a, 0x567c21, 0x906924, 0x2a6ecc, 0x8a53d6, 0x0079a1, 0x3760bf,
        ])
    case (.catppuccin, .dark):
        return hexPalette([
            0x45475a, 0xf38ba8, 0xa6e3a1, 0xf9e2af, 0x89b4fa, 0xf5c2e7, 0x94e2d5, 0xbac2de,
            0x585b70, 0xf38ba8, 0xa6e3a1, 0xf9e2af, 0x89b4fa, 0xf5c2e7, 0x94e2d5, 0xa6adc8,
        ])
    case (.catppuccin, .light):
        return hexPalette([
            0x5c5f77, 0xd20f39, 0x378a25, 0xa76a16, 0x1e66f5, 0xb25a9a, 0x15858b, 0xacb0be,
            0x6c6f85, 0xd20f39, 0x378a25, 0xa76a16, 0x1e66f5, 0xb25a9a, 0x15858b, 0xbcc0cc,
        ])
    case (.oneDark, .dark):
        return hexPalette([
            0x21252b, 0xe06c75, 0x98c379, 0xe5c07b, 0x61afef, 0xc678dd, 0x56b6c2, 0xabb2bf,
            0x5c6370, 0xe06c75, 0x98c379, 0xe5c07b, 0x61afef, 0xc678dd, 0x56b6c2, 0xc8ccd4,
        ])
    case (.oneDark, .light):
        return hexPalette([
            0x383a42, 0xd95245, 0x468e46, 0xaa7401, 0x4078f2, 0xa626a4, 0x0184bc, 0xa0a1a7,
            0x696c77, 0xd95245, 0x468e46, 0xaa7401, 0x4078f2, 0xa626a4, 0x0184bc, 0xfafafa,
        ])
    case (.monokai, .dark):
        return hexPalette([
            0x333333, 0xd5638b, 0x86b42b, 0xb3b42b, 0x7386cb, 0x987ace, 0x56adbc, 0xe3e3dd,
            0x666666, 0xf9377d, 0xa6e22e, 0xe2e22e, 0x819aff, 0xae81ff, 0x66d9ef, 0xf8f8f2,
        ])
    case (.monokai, .light):
        return hexPalette([
            0x272822, 0xd32664, 0x5c7627, 0x727227, 0x5d6ca7, 0x7d61af, 0x43767c, 0xc9c7b8,
            0x75715e, 0xe4266a, 0x648128, 0x797a27, 0x6273b4, 0x8868c1, 0x468088, 0xf9f8f1,
        ])
    case (.rosePine, .dark):
        return hexPalette([
            0x26233a, 0xeb6f92, 0x46829a, 0xf6c177, 0x9ccfd8, 0xc4a7e7, 0xebbcba, 0xe0def4,
            0x6e6a86, 0xeb6f92, 0x46829a, 0xf6c177, 0x9ccfd8, 0xc4a7e7, 0xebbcba, 0xe0def4,
        ])
    case (.rosePine, .light):
        return hexPalette([
            0x575279, 0xa9617a, 0x286983, 0x8f6e5f, 0x567c91, 0x806f9c, 0x976a7c, 0xdfdad9,
            0x9893a5, 0xa9617a, 0x286983, 0x8f6e5f, 0x567c91, 0x806f9c, 0x976a7c, 0xf2e9e1,
        ])
    case (.everforest, .dark):
        return hexPalette([
            0x475258, 0xe67e80, 0xa7c080, 0xdbbc7f, 0x7fbbb3, 0xd699b6, 0x83c092, 0xd3c6aa,
            0x7a8478, 0xe67e80, 0xa7c080, 0xdbbc7f, 0x7fbbb3, 0xd699b6, 0x83c092, 0xd3c6aa,
        ])
    case (.everforest, .light):
        return hexPalette([
            0x5c6a72, 0xbd5d5e, 0x718143, 0x837a50, 0x4a819f, 0x9d6a96, 0x4b8576, 0xedeada,
            0x829181, 0xbd5d5e, 0x718143, 0x837a50, 0x4a819f, 0x9d6a96, 0x4b8576, 0xf8f5e4,
        ])
    case (.ayu, .dark):
        return hexPalette([
            0x171b24, 0xf06b5c, 0xbfe76d, 0xe6b752, 0x3bbbf4, 0xd09ffd, 0x84ceb5, 0xd2d6dc,
            0x686868, 0xf39184, 0xd5ff80, 0xffcd66, 0x73d0ff, 0xdfbfff, 0x95e6cb, 0xe3e6ea,
        ])
    case (.ayu, .light):
        return hexPalette([
            0x86878c, 0xbd5f5f, 0x67850f, 0x9e7411, 0x2582b2, 0x8d6caf, 0x3f876f, 0xadaeb1,
            0x939498, 0xbd5f5f, 0x67850f, 0x9e7411, 0x2582b2, 0x8d6caf, 0x3f876f, 0xc5c5c8,
        ])
    }
}
