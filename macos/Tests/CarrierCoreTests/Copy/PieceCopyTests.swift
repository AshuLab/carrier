import Foundation
import Testing

@testable import CarrierCore

// The words the pieces of `Carrier/UI/` say by themselves (an accessibility label, a help, a built-in label), each a copy key. The pieces are looked at in the opened
// app and in the pieces gallery; here the keys are asserted in both languages, with the plural where the English varies by count.

private func both(_ words: (Bundle?, Locale) -> String) -> (en: String, es: String) { (words(english.bundle, english.locale), words(spanish.bundle, spanish.locale)) }

@Test func theBuiltInWordsOfTheCheckButtonAreKeysInBothLanguages() {
    let pairs: [((Bundle?, Locale) -> String, String, String)] = [
        ({ Copy.pieceCheckAgain(bundle: $0, locale: $1) }, "Check again", "Comprobar de nuevo"),
        ({ Copy.pieceChecking(bundle: $0, locale: $1) }, "Checking…", "Comprobando…"),
        ({ Copy.pieceUpToDate(bundle: $0, locale: $1) }, "Up to date", "Al día"),
        ({ Copy.pieceCheckFailed(bundle: $0, locale: $1) }, "Check failed", "Falló la comprobación"),
    ]
    for (words, en, es) in pairs {
        let said = both(words)
        #expect(said.en == en && said.es == es, Comment(rawValue: en))
    }
}

@Test func theLabelsOfTheToolbarAndSidebarSearchPiecesAreKeysInBothLanguages() {
    let pairs: [((Bundle?, Locale) -> String, String, String)] = [
        ({ Copy.pieceSearch(bundle: $0, locale: $1) }, "Search", "Buscar"),
        ({ Copy.pieceCloseSearch(bundle: $0, locale: $1) }, "Close search", "Cerrar la búsqueda"),
        ({ Copy.pieceCloseSearchHelp(bundle: $0, locale: $1) }, "Close search (Esc)", "Cerrar la búsqueda (Esc)"),
        ({ Copy.pieceClear(bundle: $0, locale: $1) }, "Clear", "Borrar"),
        ({ Copy.pieceClearSearch(bundle: $0, locale: $1) }, "Clear search", "Borrar la búsqueda"),
    ]
    for (words, en, es) in pairs {
        let said = both(words)
        #expect(said.en == en && said.es == es, Comment(rawValue: en))
    }
}

@Test func theOtherPiecesSayTheirWordsInBothLanguages() {
    let pairs: [((Bundle?, Locale) -> String, String, String)] = [
        ({ Copy.pieceCopyCode(bundle: $0, locale: $1) }, "Copy the code", "Copiar el código"),
        ({ Copy.pieceFoldShowLess(bundle: $0, locale: $1) }, "Show less", "Mostrar menos"),
        ({ Copy.pieceChosen(bundle: $0, locale: $1) }, "Chosen", "Elegida"),
        ({ Copy.pieceCopyDetails(bundle: $0, locale: $1) }, "Copy details", "Copiar los detalles"),
        ({ Copy.pieceCopied(bundle: $0, locale: $1) }, "Copied", "Copiado"),
        ({ Copy.pieceTryAgain(bundle: $0, locale: $1) }, "Try again", "Intentar de nuevo"),
        ({ Copy.pieceBrandDevelopment(bundle: $0, locale: $1) }, "Carrier, development build", "Carrier, versión de desarrollo"),
        ({ Copy.pieceDevMode(bundle: $0, locale: $1) }, "DEV MODE", "MODO DEV"),
        ({ Copy.piecePreview(bundle: $0, locale: $1) }, "Preview", "Vista previa"),
        ({ Copy.pieceNumberLess(bundle: $0, locale: $1) }, "Less", "Menos"),
        ({ Copy.pieceNumberMore(bundle: $0, locale: $1) }, "More", "Más"),
        ({ Copy.piecePullRequest(number: "736", bundle: $0, locale: $1) }, "PR #736", "PR #736"),
        ({ Copy.pieceTitleWriting(title: "Fix the upload", bundle: $0, locale: $1) }, "Fix the upload, writing a new title", "Fix the upload, escribiendo un título nuevo"),
        ({ Copy.pieceProgress(done: 3, total: 12, bundle: $0, locale: $1) }, "3 of 12", "3 de 12"),
    ]
    for (words, en, es) in pairs {
        let said = both(words)
        #expect(said.en == en && said.es == es, Comment(rawValue: en))
    }
}

@Test func theCountsOfThePiecesTakeTheirPluralInEachLanguage() {
    let one = both { Copy.pieceFiltersApplied(count: 1, bundle: $0, locale: $1) }
    let three = both { Copy.pieceFiltersApplied(count: 3, bundle: $0, locale: $1) }
    #expect(one.en == "1 filter applied" && one.es == "1 filtro aplicado")
    #expect(three.en == "3 filters applied" && three.es == "3 filtros aplicados")
    let oneMore = both { Copy.pieceFoldShowMore(count: 1, bundle: $0, locale: $1) }
    let manyMore = both { Copy.pieceFoldShowMore(count: 12, bundle: $0, locale: $1) }
    #expect(oneMore.en == "Show 1 more line" && oneMore.es == "Mostrar 1 línea más")
    #expect(manyMore.en == "Show 12 more lines" && manyMore.es == "Mostrar 12 líneas más")
}
