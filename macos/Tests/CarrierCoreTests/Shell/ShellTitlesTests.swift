import Foundation
import Testing

@testable import CarrierCore

// The words the enums give (the shortcuts and their groups, the themes, the accents, the tints, the line heights, the icon sets and styles, the recognizers, the cleanup
// servers, the idle close and the marks of a project): copy keys in both languages. English is asserted as it always was; the raw values are what is stored and never change.

private let b = spanish.bundle
private let l = spanish.locale
private let en = english.bundle
private let el = english.locale

@Test func theShortcutsAndTheirGroupsAreInSpanish() {
    #expect(ShortcutGroup.allCases.map { $0.title(bundle: b, locale: l) } == ["Ir a", "Sesiones", "Conversación", "Carrier"])
    #expect(ShortcutCommand.allCases.map { $0.title(bundle: b, locale: l) } == [
        "Inicio", "Sesiones", "Carrier", "Archivo", "Atrás", "Adelante", "Nueva sesión", "Buscar", "Sesión siguiente", "Sesión anterior", "Archivar la sesión",
        "Ir al cuadro de mensaje", "Detener al agente", "Ir al último mensaje", "Plegar o desplegar las llamadas a herramientas", "Copiar la última respuesta",
        "Iniciar o detener Carrier", "Pausar o reanudar la admisión", "Buscar epics listos ahora",
    ])
}

@Test func theShortcutsAndTheirGroupsSayTheSameEnglishAsBefore() {
    #expect(ShortcutGroup.allCases.map { $0.title(bundle: en, locale: el) } == ["Go to", "Sessions", "Conversation", "Carrier"])
    #expect(ShortcutCommand.allCases.map { $0.title(bundle: en, locale: el) } == [
        "Home", "Sessions", "Carrier", "Archive", "Back", "Forward", "New session", "Search", "Next session", "Previous session", "Archive the session",
        "Focus the message box", "Stop the agent", "Jump to the latest message", "Fold or unfold the tool calls", "Copy the last answer",
        "Start or stop Carrier", "Pause or resume intake", "Look for ready epics now",
    ])
    // what is stored and what the key monitor finds a shortcut by does not depend on the words
    #expect(ShortcutGroup.allCases.map(\.rawValue) == ["go-to", "sessions", "conversation", "carrier"])
    #expect(ShortcutCommand.newSession.rawValue == "newSession" && ShortcutCommand.checkNow.rawValue == "checkNow")
}

@Test func theKeybindingsPageIsFoundByTheSpanishTitlesOfItsRows() {
    let index = buildSettingsIndex(bundle: b, locale: l)
    for command in ShortcutCommand.allCases {
        let entry = index.first { $0.page == .keybindings && $0.rowID == command.rawValue }
        #expect(entry?.title == command.title(bundle: b, locale: l) && entry?.group == command.group.title(bundle: b, locale: l), Comment(rawValue: command.rawValue))
        #expect(entry?.groupID == command.group.rawValue)
    }
    let found = settingsResults("nueva sesión", in: index, bundle: b, locale: l)
    #expect(found.contains { $0.page == .keybindings && $0.rowID == "newSession" && $0.title == "Nueva sesión" && $0.group == "Sesiones" })
    #expect(settingsResults("plegar herramientas", in: index, bundle: b, locale: l).contains { $0.page == .keybindings && $0.rowID == "foldTools" })
    #expect(settingsResults("Atajos de teclado", in: index, bundle: b, locale: l).first.map { $0.isPage && $0.page == .keybindings } == true)
}

@Test func theThemesTheAccentsTheTintsAndTheLineHeightsAreInSpanish() {
    #expect(Theme.allCases.map { $0.title(bundle: b, locale: l) } == ["Carrier", "Grafito", "Océano", "Bosque", "Atardecer", "Papel", "Rosa", "Lavanda", "Medianoche"])
    #expect(AccentColor.allCases.map { $0.title(bundle: b, locale: l) } == ["Azul", "Morado", "Rosa", "Rojo", "Naranja", "Verde", "Grafito"])
    #expect(AccentColor.own(RGBA(hex: 0x12ab9c)).title(bundle: b, locale: l) == "Personalizado")
    #expect(Tint.allCases.map { $0.title(bundle: b, locale: l) } == ["Apagado", "Sutil", "Intenso"])
    #expect(LineHeight.allCases.map { $0.title(bundle: b, locale: l) } == ["Ajustada", "Normal", "Holgada"])
}

@Test func theThemesTheAccentsTheTintsAndTheLineHeightsSayTheSameEnglishAsBefore() {
    #expect(Theme.allCases.map { $0.title(bundle: en, locale: el) } == Theme.allCases.map(\.rawValue.capitalized))
    #expect(Theme.allCases.map(\.rawValue) == ["carrier", "graphite", "ocean", "forest", "sunset", "paper", "rose", "lavender", "midnight"])
    #expect(AccentColor.allCases.map { $0.title(bundle: en, locale: el) } == ["Blue", "Purple", "Pink", "Red", "Orange", "Green", "Graphite"])
    #expect(AccentColor.allCases.map { $0.title(bundle: en, locale: el) } == AccentColor.allCases.map(\.rawValue.capitalized))
    #expect(AccentColor.own(RGBA(hex: 0x12ab9c)).title(bundle: en, locale: el) == "Custom")
    #expect(Tint.allCases.map { $0.title(bundle: en, locale: el) } == ["Off", "Subtle", "Strong"])
    #expect(LineHeight.allCases.map { $0.title(bundle: en, locale: el) } == ["Tight", "Normal", "Loose"])
    #expect(Tint.allCases.map(\.rawValue) == ["off", "subtle", "strong"] && LineHeight.allCases.map(\.rawValue) == ["tight", "normal", "loose"])
}

@Test func theIconSetsTheIconStylesTheRecognizersAndTheCleanupServersAreInBothLanguages() {
    #expect(IconSet.allCases.map { $0.title(bundle: en, locale: el) } == ["Tabler", "Lucide", "SF Symbols"])
    #expect(IconSet.allCases.map { $0.title(bundle: b, locale: l) } == ["Tabler", "Lucide", "SF Symbols"])
    #expect(IconStyle.allCases.map { $0.title(bundle: en, locale: el) } == ["Count and bar", "Count only", "Bar only"])
    #expect(IconStyle.allCases.map { $0.title(bundle: b, locale: l) } == ["Contador y barra", "Solo el contador", "Solo la barra"])
    #expect(RecognizerID.allCases.map { $0.title(bundle: en, locale: el) } == ["Apple", "FluidAudio", "Whisper"])
    #expect(RecognizerID.allCases.map { $0.title(bundle: b, locale: l) } == ["Apple", "FluidAudio", "Whisper"])
    #expect(CleanupServer.allCases.map { $0.title(bundle: en, locale: el) } == ["LM Studio", "Ollama"])
    #expect(CleanupServer.allCases.map { $0.title(bundle: b, locale: l) } == ["LM Studio", "Ollama"])
    #expect(IconStyle.allCases.map(\.rawValue) == ["countAndBar", "countOnly", "barOnly"] && IconSet.allCases.map(\.rawValue) == ["tabler", "lucide", "sfSymbols"])
}

@Test func theColorsAndTheMarksOfAProjectAreNamedInBothLanguages() {
    #expect(ProjectColor.allCases.map { $0.title(bundle: en, locale: el) } == ["Red", "Orange", "Yellow", "Green", "Teal", "Blue", "Purple", "Pink"])
    #expect(ProjectColor.allCases.map { $0.title(bundle: b, locale: l) } == ["Rojo", "Naranja", "Amarillo", "Verde", "Verde azulado", "Azul", "Morado", "Rosa"])
    #expect(projectIconMarks.map { projectMarkTitle($0, bundle: en, locale: el) } == ["Code", "Terminal", "Cube", "Book", "Home", "Bolt", "Brain", "Star"])
    #expect(projectIconMarks.map { projectMarkTitle($0, bundle: b, locale: l) } == ["Código", "Terminal", "Cubo", "Libro", "Casa", "Rayo", "Cerebro", "Estrella"])
    // a mark written in projects.json by hand that the picker does not offer shows by its own name
    #expect(projectMarkTitle(.brush, bundle: b, locale: l) == "Brush")
}
