import CarrierCore
import SwiftUI

/// A conversation that is not one: every piece of `Carrier/UI/` in each state its catalog entry (`docs/ui.md`) lists, light or dark, drawn by the
/// real pieces with made-up data (`PiecesGalleryData`), to look at. Only under `--fixture`, for the session the fixture lists with `sessionId`;
/// no host is asked anything. Its switch keeps its state in the view and never in the preferences, and the language is the app's: to see it in
/// Spanish, Carrier Dev is opened again with `-AppleLanguages (es)`. Hover and pressed are the live pieces' own: point at one and press it.
/// `check-structure.sh` fails when a piece has no `GalleryEntry` here.
struct PiecesGalleryView: View {
    static let sessionId = "b4000000-0000-4000-8000-000000000003"
    static func shows(_ id: String) -> Bool { id == sessionId && CommandLine.arguments.contains("--fixture") }

    @Environment(\.colorScheme) private var windowScheme
    @Environment(\.pieceTheme) private var window
    @State private var chosen: Bool?

    private var dark: Bool { chosen ?? (windowScheme == .dark) }

    var body: some View {
        // the surfaces of the scheme that is chosen: `AppTheme` follows the window's appearance and not this subtree's colour scheme
        let preferences = AppPreferences()
        let surfaces = themeSurfaces(preferences.theme, scheme: dark ? .dark : .light, accent: preferences.accent, tint: preferences.tint, translucent: false)
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s30) {
                header
                section(.buttons) { PiecesGalleryButtons() }
                section(.cards) { PiecesGalleryCards() }
                section(.chips) { PiecesGalleryChips() }
                section(.feedback) { PiecesGalleryFeedback() }
                section(.fields) { PiecesGalleryFields() }
                section(.icons) { PiecesGalleryIcons() }
                section(.layout) { PiecesGalleryLayout() }
                section(.meters) { PiecesGalleryMeters() }
                section(.rows) { PiecesGalleryRows() }
                section(.selects) { PiecesGallerySelects() }
            }
            .padding(.horizontal, Tokens.Space.s40).padding(.vertical, Tokens.Space.s16)
            .frame(maxWidth: 900, alignment: .leading).frame(maxWidth: .infinity)
        }
        .font(.scaled(13))
        .background(Color(surfaces.window), ignoresSafeAreaEdges: .all)
        .environment(\.colorScheme, dark ? .dark : .light)
        .environment(\.pieceTheme, PieceTheme(surfaces: surfaces, iconWeight: window.iconWeight, iconSet: window.iconSet, statesByShape: window.statesByShape))
        .tint(surfaces.accent.map(Color.init))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s8) {
            Text(Copy.piecesTitle()).scaledFont(20, weight: .semibold)
            Text(Copy.piecesHint()).foregroundStyle(.secondary)
            SegmentedChoice(
                options: [(value: false, title: Copy.piecesScheme(which: .light), icon: nil), (value: true, title: Copy.piecesScheme(which: .dark), icon: nil)],
                selection: Binding(get: { dark }, set: { chosen = $0 }))
        }
    }

    private func section<Content: View>(_ kind: Copy.PiecesKind, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s18) {
            Text(Copy.piecesKind(which: kind)).sectionLabel().tracking(0.6)
            content()
        }
    }
}

/// A text of the gallery's sample data: a made-up sentence or word in the language of the app, so that what a piece does with words can be seen.
func sample(_ which: Copy.PieceSample) -> String { Copy.pieceSample(which: which) }

/// The entry of a piece (or of the pieces that are drawn together, `names` after the first): its name over its states.
struct GalleryEntry<Content: View>: View {
    let names: [String]
    @ViewBuilder let content: Content

    init(_ names: String..., @ViewBuilder content: () -> Content) {
        self.names = names
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s8) {
            Text(names.joined(separator: " · ")).scaledFont(13, weight: .semibold, design: .monospaced)
            // the states of one piece wrap like words, side by side
            FlowLayout(spacing: Tokens.Space.s20) { content }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One state of a piece: its words over the piece in that state.
struct GalleryState<Content: View>: View {
    let state: Copy.PieceState
    @ViewBuilder let content: Content

    init(_ state: Copy.PieceState, @ViewBuilder content: () -> Content) {
        self.state = state
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s5) {
            Text(Copy.pieceState(which: state)).scaledFont(11).foregroundStyle(.tertiary)
            content
        }
    }
}
