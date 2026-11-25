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
    static let radius: CGFloat = Tokens.Radius.tile
    /// 24 muted colours: 12 hues, each in a fuller and a greyer tone, the brightness of each chosen so the white letters keep at least 4.5:1.
    static let palette: [Color] = [
        Tokens.ProjectIcon.p01, Tokens.ProjectIcon.p02, Tokens.ProjectIcon.p03, Tokens.ProjectIcon.p04, Tokens.ProjectIcon.p05, Tokens.ProjectIcon.p06,
        Tokens.ProjectIcon.p07, Tokens.ProjectIcon.p08, Tokens.ProjectIcon.p09, Tokens.ProjectIcon.p10, Tokens.ProjectIcon.p11, Tokens.ProjectIcon.p12,
        Tokens.ProjectIcon.p13, Tokens.ProjectIcon.p14, Tokens.ProjectIcon.p15, Tokens.ProjectIcon.p16, Tokens.ProjectIcon.p17, Tokens.ProjectIcon.p18,
        Tokens.ProjectIcon.p19, Tokens.ProjectIcon.p20, Tokens.ProjectIcon.p21, Tokens.ProjectIcon.p22, Tokens.ProjectIcon.p23, Tokens.ProjectIcon.p24,
    ].map { Color($0) }

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
