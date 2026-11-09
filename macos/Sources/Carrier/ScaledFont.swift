import CarrierCore
import SwiftUI

extension Font {
    /// The system font at `base` points scaled by the person's text size; the only way a view sets a size.
    static func scaled(_ base: CGFloat, weight: Font.Weight? = nil, design: Font.Design? = nil) -> Font {
        .system(size: TypeScale.stored().size(base), weight: weight, design: design)
    }
}
