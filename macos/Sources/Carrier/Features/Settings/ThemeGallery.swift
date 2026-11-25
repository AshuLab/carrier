import CarrierCore
import SwiftUI

/// The nine themes in a grid of three, each as its light and its dark version side by side; the chosen one has the accent's edge.
struct ThemeGallery: View {
    @Binding var theme: Theme
    @Environment(\.pieceTheme) private var pieceTheme

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Tokens.Space.s10), count: 3), spacing: Tokens.Space.s10) {
            ForEach(Theme.allCases, id: \.self) { option in
                Button { theme = option } label: {
                    VStack(spacing: Tokens.Space.s8) {
                        HStack(spacing: Tokens.Space.s6) {
                            ThemePreview(theme: option, scheme: .light)
                            ThemePreview(theme: option, scheme: .dark)
                        }
                        Text(option.title()).scaledFont(12)
                    }
                    .padding(Tokens.Space.s8).frame(maxWidth: .infinity)
                    .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.card).strokeBorder(option == theme ? pieceTheme.accent : Color.secondary.opacity(0.2), lineWidth: option == theme ? 2 : 1))
                    .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title()).accessibilityAddTraits(option == theme ? .isSelected : [])
            }
        }
        .padding(.vertical, Tokens.Space.s12)
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
        HStack(spacing: Tokens.Space.none) {
            VStack(alignment: .leading, spacing: Tokens.Space.s5) {
                Capsule().fill(ink.opacity(0.25)).frame(width: 14, height: 3)
                RoundedRectangle(cornerRadius: Tokens.Radius.tiny).fill(accent.opacity(0.35)).frame(height: 8)
                Capsule().fill(ink.opacity(0.2)).frame(width: 18, height: 3)
                Capsule().fill(ink.opacity(0.2)).frame(width: 14, height: 3)
                Spacer(minLength: 0)
            }
            .padding(Tokens.Space.s6).frame(width: 34).background(Color(surfaces.sidebar))
            VStack(alignment: .leading, spacing: Tokens.Space.s6) {
                Capsule().fill(ink.opacity(0.4)).frame(width: 28, height: 4)
                VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                    Capsule().fill(ink.opacity(0.22)).frame(height: 3)
                    Capsule().fill(ink.opacity(0.22)).frame(width: 34, height: 3)
                }
                .padding(Tokens.Space.s5).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Tokens.Radius.tiny).fill(ink.opacity(0.07)))
                Spacer(minLength: 0)
                HStack(spacing: Tokens.Space.s4) {
                    Capsule().fill(ink.opacity(0.12)).frame(height: 8)
                    Capsule().fill(accent).frame(width: 14, height: 8)
                }
            }
            .padding(Tokens.Space.s6).frame(maxWidth: .infinity).background(Color(surfaces.window))
        }
        .frame(height: 84).clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.control))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.control).strokeBorder(Color.secondary.opacity(0.3), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}
