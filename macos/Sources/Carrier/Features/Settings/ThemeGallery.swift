import CarrierCore
import SwiftUI

/// The nine themes in a grid of three, each as its light and its dark version side by side; the chosen one has the accent's edge.
struct ThemeGallery: View {
    @Binding var theme: Theme

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(Theme.allCases, id: \.self) { option in
                Button { theme = option } label: {
                    VStack(spacing: 8) {
                        HStack(spacing: 6) {
                            ThemePreview(theme: option, scheme: .light)
                            ThemePreview(theme: option, scheme: .dark)
                        }
                        Text(option.title).font(.scaled(12))
                    }
                    .padding(8).frame(maxWidth: .infinity)
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(option == theme ? Color.themeAccent : Color.secondary.opacity(0.2), lineWidth: option == theme ? 2 : 1))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title).accessibilityAddTraits(option == theme ? .isSelected : [])
            }
        }
        .padding(.vertical, 12)
    }
}

/// A made-up window in one version of a theme: a sidebar with a selected row, a title, two messages and a button in the accent. Only
/// what the theme paints (the window, the sidebar, the accent); the grey of the text is a stand-in.
private struct ThemePreview: View {
    let theme: Theme
    let scheme: ThemeScheme

    var body: some View {
        let surfaces = themeSurfaces(theme, scheme: scheme, translucent: false)
        let accent = surfaces.accent.map(Color.init) ?? .accentColor
        let ink = scheme == .dark ? Color.white : Color.black
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Capsule().fill(ink.opacity(0.25)).frame(width: 14, height: 3)
                RoundedRectangle(cornerRadius: 2).fill(accent.opacity(0.35)).frame(height: 8)
                Capsule().fill(ink.opacity(0.2)).frame(width: 18, height: 3)
                Capsule().fill(ink.opacity(0.2)).frame(width: 14, height: 3)
                Spacer(minLength: 0)
            }
            .padding(6).frame(width: 34).background(Color(surfaces.sidebar))
            VStack(alignment: .leading, spacing: 6) {
                Capsule().fill(ink.opacity(0.4)).frame(width: 28, height: 4)
                VStack(alignment: .leading, spacing: 3) {
                    Capsule().fill(ink.opacity(0.22)).frame(height: 3)
                    Capsule().fill(ink.opacity(0.22)).frame(width: 34, height: 3)
                }
                .padding(5).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 4).fill(ink.opacity(0.07)))
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Capsule().fill(ink.opacity(0.12)).frame(height: 8)
                    Capsule().fill(accent).frame(width: 14, height: 8)
                }
            }
            .padding(6).frame(maxWidth: .infinity).background(Color(surfaces.window))
        }
        .frame(height: 84).clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.3), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}
