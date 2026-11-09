import AppKit
import CarrierCore
import Observation
import SwiftUI

/// The text size the person chose, for the views to read while they draw: a view that sets a font through `scaled` is drawn again when
/// the size changes, so moving the slider in Settings rescales the whole interface at once.
@Observable final class TextSize {
    static let shared = TextSize()

    private(set) var percent = TypeScale.stored().percent

    private init() {
        // any change of the defaults: what the slider writes, and what Reset removes
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [self] _ in
            let stored = TypeScale.stored().percent
            if stored != percent { percent = stored }
        }
    }

    var scale: TypeScale { TypeScale(percent: percent) }
}

extension Font {
    /// The system font at `base` points scaled by the person's text size; the only way a view sets a size.
    static func scaled(_ base: CGFloat, weight: Font.Weight? = nil, design: Font.Design? = nil) -> Font {
        .system(size: TextSize.shared.scale.size(base), weight: weight, design: design)
    }
}

extension NSFont {
    /// The system font at `base` points scaled by the person's text size.
    static func scaled(_ base: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        .systemFont(ofSize: TextSize.shared.scale.size(base), weight: weight)
    }

    /// The monospaced system font at `base` points scaled by the person's text size.
    static func scaledMono(_ base: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        .monospacedSystemFont(ofSize: TextSize.shared.scale.size(base), weight: weight)
    }

    // The menu bar and the menus are the system's chrome: the text size does not reach them.
    static let statusItemDigits = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
    static let menuTitle = NSFont.systemFont(ofSize: NSFont.menuFont(ofSize: 0).pointSize, weight: .semibold)
}

extension ColorSchemeChoice {
    /// What `NSApp.appearance` takes: nil follows the Mac.
    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// The color scheme chosen in Settings, on every window of the app: set now and again whenever the defaults change.
@MainActor func followColorScheme() {
    func apply() {
        let appearance = AppPreferences().colorScheme.appearance
        if NSApp.appearance?.name != appearance?.name { NSApp.appearance = appearance }
    }
    apply()
    NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
        MainActor.assumeIsolated { apply() }
    }
}
