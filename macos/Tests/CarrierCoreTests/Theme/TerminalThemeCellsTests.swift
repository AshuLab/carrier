import Testing

@testable import CarrierCore

/// The terminal's gallery: the app's theme as the first cell, then every theme; nil stored is the first cell.
@Suite struct TerminalThemeCellsTests {
    private func cells(app: Theme, stored: Theme?) -> TerminalThemeCells {
        terminalThemeCells(app: app, stored: stored, bundle: english.bundle, locale: english.locale)
    }

    @Test func the_first_cell_is_the_apps_theme_with_the_words_same_as_the_app_and_then_every_theme_in_order() {
        let result = cells(app: .ocean, stored: nil)
        #expect(result.cells.count == Theme.allCases.count + 1)
        #expect(result.cells[0] == ThemeCell(id: TerminalThemeCells.sameAsAppID, title: "Same as app (Ocean)", theme: .ocean))
        #expect(result.cells.dropFirst().map(\.theme) == Theme.allCases)
        #expect(result.cells.dropFirst().map(\.title) == Theme.allCases.map { $0.title(bundle: english.bundle, locale: english.locale) })
    }

    @Test func with_no_stored_theme_the_first_cell_is_the_chosen_one() {
        #expect(cells(app: .forest, stored: nil).chosen == TerminalThemeCells.sameAsAppID)
    }

    @Test func a_stored_theme_is_the_chosen_cell_and_the_first_is_not() {
        let result = cells(app: .forest, stored: .nord)
        #expect(result.chosen == Theme.nord.rawValue)
        #expect(result.cells.contains { $0.id == result.chosen && $0.theme == .nord })
    }

    @Test func a_stored_theme_equal_to_the_apps_is_chosen_as_itself_not_as_the_first_cell() {
        let result = cells(app: .nord, stored: .nord)
        #expect(result.chosen == Theme.nord.rawValue)
        #expect(result.chosen != TerminalThemeCells.sameAsAppID)
    }

    @Test func when_the_apps_theme_changes_the_first_cell_follows_it_and_stays_chosen() {
        let before = cells(app: .ocean, stored: nil), after = cells(app: .sunset, stored: nil)
        #expect(before.chosen == TerminalThemeCells.sameAsAppID && after.chosen == TerminalThemeCells.sameAsAppID)
        #expect(after.cells[0].theme == .sunset && after.cells[0].title == "Same as app (Sunset)")
        #expect(after.cells.dropFirst().map(\.id) == before.cells.dropFirst().map(\.id))
    }

    @Test func picking_a_theme_stores_it_and_picking_the_first_cell_clears_it() {
        #expect(TerminalThemeCells.stored(picking: Theme.gruvbox.rawValue) == .gruvbox)
        #expect(TerminalThemeCells.stored(picking: TerminalThemeCells.sameAsAppID) == nil)
    }

    @Test func a_theme_stored_before_the_gallery_reads_as_the_same_choice() {
        for theme in Theme.allCases { #expect(cells(app: .carrier, stored: theme).chosen == theme.rawValue) }
    }
}
