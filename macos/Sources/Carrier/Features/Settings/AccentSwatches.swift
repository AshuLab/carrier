import AppKit
import CarrierCore
import CarrierUI
import SwiftUI

/// Opens the Mac's color panel and tells what the person picks in it, until another place opens it.
@MainActor private final class ColorPanelOpener: NSObject {
    static let shared = ColorPanelOpener()
    private var picked: ((NSColor) -> Void)?

    func open(color: NSColor, picked: @escaping (NSColor) -> Void) {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.isFloatingPanel = true
        // set before the target, so showing the current color does not count as a pick
        panel.color = color
        self.picked = picked
        panel.setTarget(self)
        panel.setAction(#selector(changed(_:)))
        NSApp.activate()
        if panel.isVisible == false { place(panel, besides: NSEvent.mouseLocation) }
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    @objc private func changed(_ panel: NSColorPanel) { picked?(panel.color) }

    /// The panel has no place of its own the first time: next to the click, on the side with room, so the page it changes stays in sight.
    private func place(_ panel: NSColorPanel, besides point: NSPoint) {
        let room = (NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main)?.visibleFrame ?? .zero
        let size = panel.frame.size
        var x = point.x + 24
        if x + size.width > room.maxX { x = point.x - size.width - 24 }
        let y = min(max(point.y - size.height / 2, room.minY), room.maxY - size.height)
        panel.setFrameOrigin(NSPoint(x: max(x, room.minX), y: y))
    }
}

/// The theme's own accent, a line, the seven colors and a multicolor disc that opens the Mac's color panel, as discs; the chosen one has a ring.
/// The line says the first is the theme's and the others are choices of the person.
struct AccentSwatches: View {
    let theme: Theme
    let scheme: ThemeScheme
    @Binding var accent: AccentColor?

    var body: some View {
        HStack(spacing: Tokens.Space.s8) {
            swatch(Copy.appearanceAccentName(theme: theme.title()), color: themeSurfaces(theme, scheme: scheme, translucent: false).accent.map(Color.init) ?? .accentColor, chosen: accent == nil) { accent = nil }
            SettingsDivider(vertical: true).frame(height: 18).padding(.horizontal, Tokens.Space.s4)
            ForEach(AccentColor.allCases, id: \.self) { option in
                swatch(option.title(), color: Color(option.color), chosen: accent == option) { accent = option }
            }
            customSwatch
        }
    }

    /// A disc of every hue that opens the Mac's own color panel; once a color is picked, it fills the middle of the disc.
    private var customSwatch: some View {
        let chosen = accent?.isCustom == true
        return Button {
            ColorPanelOpener.shared.open(color: accent.map { NSColor(Color($0.color)) } ?? .controlAccentColor) { picked in
                guard let rgb = picked.usingColorSpace(.sRGB) else { return }
                accent = .own(RGBA(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent))
            }
        } label: {
            ZStack {
                Circle().fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                if let accent, chosen { Circle().fill(Color(accent.color)).padding(Tokens.Space.s4) }
            }
            .frame(width: 18, height: 18)
            .padding(Tokens.Space.s3).overlay(Circle().strokeBorder(chosen ? Color.primary.opacity(0.7) : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain).help(Copy.appearanceCustomColor()).accessibilityLabel(Copy.appearanceCustomAccent()).accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private func swatch(_ name: String, color: Color, chosen: Bool, choose: @escaping () -> Void) -> some View {
        Button(action: choose) {
            Circle().fill(color).frame(width: 18, height: 18)
                .padding(Tokens.Space.s3).overlay(Circle().strokeBorder(chosen ? Color.primary.opacity(0.7) : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain).help(name).accessibilityLabel(name).accessibilityAddTraits(chosen ? .isSelected : [])
    }
}
