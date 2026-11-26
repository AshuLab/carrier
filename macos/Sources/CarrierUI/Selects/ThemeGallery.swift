import CarrierCore
import SwiftUI

/// The themes as cells in three fixed rows that fill column by column and scroll sideways, so the page keeps its height however many themes there
/// are: a cell is a light and a dark preview side by side with the name under them, the chosen one with the accent's edge. Half a column is cut at the
/// right edge while there are cells beyond it, an arrow at each side scrolls by a page of columns (hidden when it cannot scroll further), and with
/// the keyboard up and down move one cell inside a column and left and right one column, choosing as they go (`themeGalleryMove`); the gallery
/// scrolls until the chosen cell is whole. It takes the cells and the chosen one's id and says which was picked; the terminal's gallery gives it a
/// first cell of its own.
public struct ThemeGallery: View {
    let cells: [ThemeCell]
    let chosen: ThemeCell.ID
    let action: (ThemeCell.ID) -> Void

    public init(cells: [ThemeCell], chosen: ThemeCell.ID, action: @escaping (ThemeCell.ID) -> Void) {
        self.cells = cells
        self.chosen = chosen
        self.action = action
    }

    @State private var position = ScrollPosition()
    @State private var scroll = Scroll(offset: 0, content: 0, width: 0)
    @State private var viewport: CGFloat = 0
    // a click on a cell puts the keyboard in the gallery, so the arrows work right after picking one with the mouse
    @FocusState private var focused: Bool

    private static let rows = 3
    private static let gap = Tokens.Space.s10
    private static let columnsPerPage: CGFloat = 3

    /// Where the gallery is scrolled to and how long it and its window are; what the arrows show and scroll by.
    private struct Scroll: Equatable {
        var offset: CGFloat, content: CGFloat, width: CGFloat
        var farthest: CGFloat { max(0, content - width) }
        var canGoBack: Bool { offset > 1 }
        var canGoForward: Bool { offset < farthest - 1 }
    }

    private static func column(in width: CGFloat) -> CGFloat { max(0, (width - columnsPerPage * gap) / 3.5) }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(rows: Array(repeating: GridItem(.flexible(), spacing: Self.gap), count: Self.rows), spacing: Self.gap) {
                ForEach(cells) { cell in
                    ThemeCellButton(cell: cell, chosen: cell.id == chosen) {
                        focused = true
                        action(cell.id)
                    }
                        // three columns and half of the next one fill the width, so there is always something cut at the edge while there is more
                        .frame(width: Self.column(in: viewport))
                        .id(cell.id)
                }
            }
        }
        // the height is the three rows' own, whatever height is offered: flexible rows would otherwise shrink to their minimum in a view that offers little
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { viewport = $0 }
        .scrollPosition($position)
        .onScrollGeometryChange(for: Scroll.self) { geometry in
            Scroll(offset: geometry.contentOffset.x, content: geometry.contentSize.width, width: geometry.containerSize.width)
        } action: { _, new in scroll = new }
        .overlay(alignment: .leading) { arrow(.chevronLeft, name: Copy.pieceThemesEarlier(), visible: scroll.canGoBack, by: -1) }
        .overlay(alignment: .trailing) { arrow(.chevronRight, name: Copy.pieceThemesMore(), visible: scroll.canGoForward, by: 1) }
        .focusable().focusEffectDisabled().focused($focused)
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
            guard let index = cells.firstIndex(where: { $0.id == chosen }) else { return .ignored }
            let key: ThemeGalleryKey = switch press.key {
            case .upArrow: .up
            case .downArrow: .down
            case .leftArrow: .left
            default: .right
            }
            let next = themeGalleryMove(from: index, key: key, count: cells.count, rows: Self.rows)
            if next != index { action(cells[next].id) }
            return .handled
        }
        .onChange(of: chosen) { scrollToChosen(animated: true) }
        .onAppear { scrollToChosen(animated: false) }
        .accessibilityElement(children: .contain).accessibilityLabel(Copy.pieceThemes())
    }

    /// The least the gallery moves for the chosen cell to be whole.
    private func scrollToChosen(animated: Bool) {
        if animated { withAnimation(.smooth(duration: 0.25)) { position.scrollTo(id: chosen) } } else { position.scrollTo(id: chosen) }
    }

    @ViewBuilder private func arrow(_ icon: AppIcon, name: String, visible: Bool, by direction: CGFloat) -> some View {
        if visible {
            IconButton(icon: icon, name: name) {
                withAnimation(.smooth(duration: 0.3)) { page(direction) }
            }
            .background(.regularMaterial, in: Circle()).overlay(Circle().strokeBorder(Color.secondary.opacity(0.3), lineWidth: 0.5))
            .padding(.horizontal, Tokens.Space.s4).transition(.opacity)
        }
    }

    /// About a page of columns: three of them.
    private func page(_ direction: CGFloat) {
        let by = direction * Self.columnsPerPage * (Self.column(in: scroll.width) + Self.gap)
        position.scrollTo(x: min(max(0, scroll.offset + by), scroll.farthest))
    }
}

/// One cell: the light and the dark preview of a theme side by side, its name under them, and the accent's edge when it is the chosen one.
private struct ThemeCellButton: View {
    let cell: ThemeCell
    let chosen: Bool
    let action: () -> Void
    @Environment(\.pieceTheme) private var pieceTheme

    var body: some View {
        Button(action: action) {
            VStack(spacing: Tokens.Space.s8) {
                HStack(spacing: Tokens.Space.s6) {
                    ThemePreview(theme: cell.theme, scheme: .light)
                    ThemePreview(theme: cell.theme, scheme: .dark)
                }
                Text(cell.title).scaledFont(12).lineLimit(1)
            }
            .padding(Tokens.Space.s8).frame(maxWidth: .infinity)
            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.card).strokeBorder(chosen ? pieceTheme.accent : Color.secondary.opacity(0.2), lineWidth: chosen ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(cell.title).accessibilityAddTraits(chosen ? .isSelected : [])
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
                Capsule().fill(ink.opacity(0.4)).frame(maxWidth: 28).frame(height: 4)
                VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                    Capsule().fill(ink.opacity(0.22)).frame(height: 3)
                    Capsule().fill(ink.opacity(0.22)).frame(maxWidth: 34).frame(height: 3)
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
