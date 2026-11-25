import Foundation
import Testing

@testable import CarrierCore

// The fixture galleries (under --fixture, in Settings' folder of the app) say their own words through copy keys, so each shows the language of the app.
// Their data (`PiecesGalleryData`) is code, paths, numbers and names of tools, which no language changes, and has no count that varies a word.

@Test func thePiecesGalleryReadsInSpanishWithItsSampleWordsItsStatesItsKindsAndItsTitle() {
    func sample(_ which: Copy.PieceSample) -> String { Copy.pieceSample(which: which, bundle: spanish.bundle, locale: spanish.locale) }
    func state(_ which: Copy.PieceState) -> String { Copy.pieceState(which: which, bundle: spanish.bundle, locale: spanish.locale) }
    #expect(Copy.piecesTitle(bundle: spanish.bundle, locale: spanish.locale) == "Piezas")
    #expect(Copy.piecesHint(bundle: spanish.bundle, locale: spanish.locale).hasPrefix("Cada pieza de la app en los estados"))
    #expect(Copy.piecesHint(bundle: spanish.bundle, locale: spanish.locale).hasSuffix("-AppleLanguages (en)."))
    #expect(Copy.piecesScheme(which: .light, bundle: spanish.bundle, locale: spanish.locale) == "Claro" && Copy.piecesScheme(which: .dark, bundle: spanish.bundle, locale: spanish.locale) == "Oscuro")
    let kinds: [(Copy.PiecesKind, String)] = [
        (.buttons, "Botones"), (.cards, "Tarjetas"), (.chips, "Chips"), (.feedback, "Avisos"), (.fields, "Campos"), (.icons, "Iconos"), (.layout, "Disposición"), (.meters, "Medidores"),
        (.rows, "Filas"), (.selects, "Selectores"),
    ]
    for (kind, words) in kinds { #expect(Copy.piecesKind(which: kind, bundle: spanish.bundle, locale: spanish.locale) == words) }
    let samples: [(Copy.PieceSample, String)] = [
        (.account, "Cuenta de trabajo"), (.action, "Hacerlo"), (.cancel, "Ahora no"), (.choiceOne, "Bajo"), (.choiceTwo, "Medio"), (.choiceThree, "Alto"), (.field, "Nombre"), (.group, "Un grupo"),
        (.hint, "Inténtalo de nuevo en un momento."), (.label, "Una etiqueta"), (.placeholder, "Escribe aquí"), (.problem, "Este valor no es válido."), (.query, "Algo escrito"), (.row, "Un ajuste"),
        (.rowDetail, "Qué cambia, en una línea."), (.tag, "Pregunta"), (.title, "Algo que contar"),
    ]
    for (which, words) in samples { #expect(sample(which) == words) }
    #expect(sample(.detail) == "Una frase que dice qué significa y qué hacer después.")
    #expect(sample(.groupFooter) == "Una nota más larga sobre todo el grupo, debajo.")
    let states: [(Copy.PieceState, String)] = [
        (.normal, "Normal"), (.disabled, "Desactivado"), (.loading, "Cargando"), (.empty, "Vacío"), (.noResults, "Sin resultados"), (.withDetail, "Con detalle"), (.withoutDetail, "Sin detalle"),
        (.withActions, "Con acciones"), (.folded, "Plegado"), (.high, "Casi lleno"), (.tool, "Marca de la herramienta"), (.byShape, "Distinguido por su forma"),
    ]
    for (which, words) in states { #expect(state(which) == words) }
}

@Test func thePiecesGalleryKeepsItsEnglishWordsInEnglish() {
    #expect(Copy.piecesTitle(bundle: english.bundle, locale: english.locale) == "Pieces")
    #expect(Copy.pieceSample(which: .row, bundle: english.bundle, locale: english.locale) == "A setting")
    #expect(Copy.pieceSample(which: .rowDetail, bundle: english.bundle, locale: english.locale) == "What it changes, in one line.")
    #expect(Copy.pieceState(which: .noResults, bundle: english.bundle, locale: english.locale) == "No results")
    #expect(Copy.piecesKind(which: .feedback, bundle: english.bundle, locale: english.locale) == "Feedback")
}

@Test func theNoticesGalleryReadsInEnglishAndInSpanish() {
    func both(_ words: (Bundle?, Locale) -> String) -> (en: String, es: String) { (words(english.bundle, english.locale), words(spanish.bundle, spanish.locale)) }
    let group = both { Copy.noticesGalleryGroupBox(bundle: $0, locale: $1) }
    #expect(group.en == "Over the message box" && group.es == "Sobre la caja de mensajes")
    let caption = both { Copy.noticesGalleryCaptionAsleepChosen(bundle: $0, locale: $1) }
    #expect(caption.en == "Asleep, with something chosen that waits for the wake" && caption.es == "Dormida, con algo elegido que espera al despertar")
    let sample = both { Copy.noticesGallerySampleApprovalQuestion(bundle: $0, locale: $1) }
    #expect(sample.en == "Allow Bash?" && sample.es == "¿Permitir Bash?")
    let stopped = both { Copy.noticesGallerySampleEpicStoppedTitle(bundle: $0, locale: $1) }
    #expect(stopped.en == "Review limit reached" && stopped.es == "Se alcanzó el límite de revisión")
    // the refusal the gallery builds says the sign-in sentence of the host's code in each language
    let refusal = both { Copy.text("agent.notLoggedIn", ["agent": "Claude"], bundle: $0, locale: $1) ?? "" }
    #expect(refusal.en == "Claude is not logged in; run \"claude\" once to log in" && refusal.es.hasPrefix("Claude no ha iniciado sesión"))
}
