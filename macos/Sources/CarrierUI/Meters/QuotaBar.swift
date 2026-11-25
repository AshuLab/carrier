import SwiftUI

/// A quota's track, 8 pt: the use that stays (`solid`, a share of the whole) is solid (the theme's accent, orange from 90 %) and the use the next reset
/// gives back (`hatched`) is hatched after it. `QuotaPercent` is the number of the same use.
struct QuotaBar: View {
    let solid: Double
    let hatched: Double
    var height: CGFloat = 8
    @Environment(\.pieceTheme) private var theme

    var body: some View {
        let tint = solid + hatched >= 0.9 ? Color.orange : theme.accent
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Color.primary.opacity(0.12)
                LinearGradient(colors: [tint.opacity(0.8), tint], startPoint: .leading, endPoint: .trailing).frame(width: width * solid)
                Hatch().stroke(tint, lineWidth: 1.5).background(tint.opacity(0.3)).frame(width: width * hatched).offset(x: width * solid)
            }
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        }
        .frame(height: height).animation(.easeOut(duration: 0.25), value: solid + hatched).accessibilityHidden(true)
    }
}

private struct Hatch: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = -rect.height
        while x < rect.width {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += 4
        }
        return path
    }
}
