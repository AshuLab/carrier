import AppKit
import CarrierCore
import SwiftUI

/// A project's icon: its image, or its mark or initials in white on its color, in a rounded square of glass tinted with it. A bright arc goes
/// round its edge while an agent works (`WorkingRing`). In a sidebar row it is neutral until the row is selected or hovered (`rowActive`).
struct ProjectIcon: View {
    /// The letters inside the tile, when it has no mark.
    let initials: String
    let color: Color
    var mark: AppIcon? = nil
    var image: NSImage? = nil
    var working = false
    /// The ring is the cyan of a session that waits for something it started, not the violet of one that works.
    var background = false
    /// The ring goes once round in green, fast, after `working`: the agent just ended its turn. The owner takes it away a moment later.
    var finished = false
    @Environment(\.rowActive) private var active
    static let size: CGFloat = 32
    static let radius: CGFloat = 9
    /// 24 muted colours: 12 hues, each in a fuller and a greyer tone, the brightness of each chosen so the white letters keep at least 4.5:1.
    static let palette: [Color] = [
        (0.042, 0.52, 0.64), (0.125, 0.52, 0.52), (0.208, 0.52, 0.49), (0.292, 0.52, 0.51), (0.375, 0.52, 0.51), (0.458, 0.52, 0.51),
        (0.542, 0.52, 0.56), (0.625, 0.52, 0.64), (0.708, 0.52, 0.64), (0.792, 0.52, 0.64), (0.875, 0.52, 0.64), (0.958, 0.52, 0.64),
        (0.042, 0.36, 0.50), (0.125, 0.36, 0.50), (0.208, 0.36, 0.48), (0.292, 0.36, 0.50), (0.375, 0.36, 0.50), (0.458, 0.36, 0.49),
        (0.542, 0.36, 0.50), (0.625, 0.36, 0.50), (0.708, 0.36, 0.50), (0.792, 0.36, 0.50), (0.875, 0.36, 0.50), (0.958, 0.36, 0.50),
    ].map { Color(hue: $0.0, saturation: $0.1, brightness: $0.2) }

    var body: some View {
        Group {
            if let image {
                Color.clear
                    .frame(width: Self.size, height: Self.size)
                    .glassEffect(.regular, in: .rect(cornerRadius: Self.radius))
                    .overlay {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: Self.size, height: Self.size)
                            .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
                            .saturation(active ? 1 : 0)
                            .opacity(active ? 1 : 0.72)
                    }
            } else {
                Color.clear
                    .frame(width: Self.size, height: Self.size)
                    .glassEffect(active ? .regular.tint(color) : .regular, in: .rect(cornerRadius: Self.radius))
                    .overlay {
                        if let mark {
                            Glyph(mark, size: 15, bold: true).foregroundStyle(active ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                        } else {
                            Text(initials).scaledFont(initials.count > 2 ? 10.5 : 12, weight: .semibold).tracking(initials.count > 2 ? 0 : 0.3)
                                .foregroundStyle(active ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                        }
                    }
            }
        }
        .animation(.easeOut(duration: 0.15), value: active)
        .overlay { if working || finished { WorkingRing(finished: finished && working == false, background: background).transition(.opacity) } }
        .animation(.easeOut(duration: 0.3), value: finished)
    }
}
