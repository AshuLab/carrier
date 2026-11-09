import AppKit
import CarrierCore
import SwiftUI

extension Font {
    /// The system font at `base` points scaled by the person's text size; the only way a view sets a size.
    static func scaled(_ base: CGFloat, weight: Font.Weight? = nil, design: Font.Design? = nil) -> Font {
        .system(size: TypeScale.stored().size(base), weight: weight, design: design)
    }
}

extension NSFont {
    /// The system font at `base` points scaled by the person's text size.
    static func scaled(_ base: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        .systemFont(ofSize: TypeScale.stored().size(base), weight: weight)
    }

    /// The monospaced system font at `base` points scaled by the person's text size.
    static func scaledMono(_ base: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        .monospacedSystemFont(ofSize: TypeScale.stored().size(base), weight: weight)
    }

    // The menu bar and the menus are the system's chrome: the text size does not reach them.
    static let statusItemDigits = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
    static let menuTitle = NSFont.systemFont(ofSize: NSFont.menuFont(ofSize: 0).pointSize, weight: .semibold)
}
