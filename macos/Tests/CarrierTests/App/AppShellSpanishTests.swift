import AppKit
import Foundation
import Testing
@testable import CarrierCore
@testable import Carrier

private let english = (bundle: Copy.bundle("en"), locale: Locale(identifier: "en_US"))
private let spanish = (bundle: Copy.bundle("es"), locale: Locale(identifier: "es_AR"))

/// The menus of the app shell in Spanish: the titles of the menu bar, the Dock, the status menu's rows, and the roles that do not look a menu up by its title.
@MainActor @Suite struct AppShellSpanishTests {
    private func table() -> ShortcutTable {
        let suite = "app-shell-spanish-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return ShortcutTable(defaults: defaults)
    }

    private func titles(_ menu: NSMenu, _ name: String) -> [String] {
        menu.items.first { $0.title == name }?.submenu?.items.filter { $0.isSeparatorItem == false }.map(\.title) ?? []
    }

    @Test func theMenuBarReadsInSpanish() {
        let menu = AppDelegate().makeMainMenu(shortcuts: table(), bundle: spanish.bundle, locale: spanish.locale)
        #expect(menu.items.map(\.title) == ["Carrier", "Archivo", "Edición", "Visualización", "Conversación", "Motor", "Terminal", "Ventana", "Ayuda"])
        #expect(titles(menu, "Carrier") == ["Acerca de Carrier", "Buscar actualizaciones…", "Ajustes…", "Servicios", "Ocultar Carrier", "Ocultar otros", "Mostrar todo", "Salir de Carrier"])
        #expect(titles(menu, "Archivo") == ["Nueva sesión", "Sesión siguiente", "Sesión anterior", "Archivar sesión", "Cerrar ventana"])
        #expect(titles(menu, "Edición") == ["Deshacer", "Rehacer", "Cortar", "Copiar", "Pegar", "Seleccionar todo", "Buscar…"])
        #expect(titles(menu, "Visualización") == [
            "Inicio", "Sesiones", "Carrier", "Archivadas", "Atrás", "Adelante", "Mostrar u ocultar la barra lateral", "Mostrar u ocultar el inspector", "Entrar en pantalla completa",
        ])
        #expect(titles(menu, "Conversación") == [
            "Enfocar la caja de mensajes", "Detener al agente", "Ir al último mensaje", "Plegar o desplegar las llamadas a herramientas", "Copiar la última respuesta",
        ])
        #expect(titles(menu, "Ventana") == ["Minimizar", "Zoom", "Traer todo al frente"])
        #expect(titles(menu, "Ayuda") == ["Carrier en GitHub"])
        #expect(titles(menu, "Terminal").first == "Nueva terminal" && titles(menu, "Terminal").contains("Dividir a la derecha") && titles(menu, "Terminal").contains("Cerrar el panel"))
    }

    @Test func theMenuBarReadsInEnglishAsBefore() {
        let menu = AppDelegate().makeMainMenu(shortcuts: table(), bundle: english.bundle, locale: english.locale)
        #expect(menu.items.map(\.title) == ["Carrier", "File", "Edit", "View", "Conversation", "Engine", "Terminal", "Window", "Help"])
        #expect(titles(menu, "Carrier") == ["About Carrier", "Check for Updates…", "Settings…", "Services", "Hide Carrier", "Hide Others", "Show All", "Quit Carrier"])
        #expect(titles(menu, "Window") == ["Minimize", "Zoom", "Bring All to Front"])
        #expect(titles(menu, "Help") == ["Carrier on GitHub"])
    }

    /// With the app in Spanish the three menus macOS asks for are still found, by their role.
    @Test func theSystemMenusAreFoundByRoleInSpanish() throws {
        let app = AppDelegate()
        let menu = app.makeMainMenu(shortcuts: table(), bundle: spanish.bundle, locale: spanish.locale)
        let shared = NSApplication.shared
        shared.servicesMenu = nil
        shared.windowsMenu = nil
        shared.helpMenu = nil
        app.setSystemMenus(of: menu)
        #expect(shared.servicesMenu?.title == "Servicios" && shared.windowsMenu?.title == "Ventana" && shared.helpMenu?.title == "Ayuda")
    }

    @Test func theDockMenuReadsInBothLanguages() {
        #expect(AppDelegate().dockMenu(bundle: spanish.bundle, locale: spanish.locale).items.map(\.title) == ["Nueva sesión", "Abrir ventana"])
        #expect(AppDelegate().dockMenu(bundle: english.bundle, locale: english.locale).items.map(\.title) == ["New Session", "Open Window"])
    }

    @Test func theTerminalMenuValidationRetitlesInSpanish() throws {
        let controls = TerminalMenuControls(bundle: spanish.bundle, locale: spanish.locale)
        let menu = AppDelegate().makeMainMenu(shortcuts: table(), terminalControls: controls, bundle: spanish.bundle, locale: spanish.locale)
        let toggle = try #require(menu.item(withTitle: "Terminal")?.submenu?.items.first { $0.action == #selector(TerminalMenuControls.toggleTerminalDrawer) })
        _ = controls.validateMenuItem(toggle)
        #expect(toggle.title == "Mostrar u ocultar la terminal")
    }

    @Test func theControlsOfTheStatusMenuReadInSpanish() {
        let menu = NSMenu()
        MenuControls(bundle: spanish.bundle, locale: spanish.locale).install(in: menu)
        #expect(menu.items.map(\.title) == ["Iniciar Carrier", "Pausar la admisión", "Comprobar GitHub ahora", "Detener Carrier"])
        let inEnglish = NSMenu()
        MenuControls(bundle: english.bundle, locale: english.locale).install(in: inEnglish)
        #expect(inEnglish.items.map(\.title) == ["Start Carrier", "Pause intake", "Check GitHub now", "Stop Carrier"])
    }

    @Test func theSleepRowAndItsSubmenuReadInSpanish() throws {
        let menu = NSMenu()
        KeepAwakeMenu(bundle: spanish.bundle, locale: spanish.locale).install(in: menu)
        let sleep = try #require(menu.items.first)
        #expect(sleep.submenu?.title == "Reposo")
        #expect(sleep.submenu?.items.filter { $0.isSeparatorItem == false }.map(\.title).suffix(2) == ["Mantener despierto durante", "Ajustes para mantener despierto…"])
    }

    @Test func theStatusMenuRowsOpenInTheLanguageOfTheApp() {
        let status = WindowController.shared
        let menu = NSMenu()
        status.addMenuItem(to: menu, bundle: spanish.bundle, locale: spanish.locale)
        status.addSettingsItem(to: menu, bundle: spanish.bundle, locale: spanish.locale)
        status.addAboutItem(to: menu, bundle: spanish.bundle, locale: spanish.locale)
        #expect(menu.items.map(\.title) == ["Abrir ventana", "Ajustes…", "Acerca de Carrier"])
    }

    // MARK: the groups of the status menu

    private func registry(terminals count: Int) -> [StandaloneTerminalSummary] {
        var registry = TerminalRegistry()
        for index in 0..<count { _ = registry.openTab(owner: .terminal(UUID()), spec: TerminalLaunchSpec(workingDirectory: "/existing/t\(index)", title: "T\(index)")) }
        return registry.standaloneTerminals()
    }

    private func waiting(_ count: Int) -> [SessionRow] {
        (0..<count).map { SessionRow(id: "s\($0)", title: "Session \($0)", workspace: "w", agent: "a", state: .waiting, updatedAt: Date(timeIntervalSince1970: 0), archived: false) }
    }

    private func entry(_ outcome: DictationOutcome) -> DictationEntry {
        DictationEntry(started: Date().addingTimeInterval(-300), text: "hello there", model: "m", transcription: 1, audio: 2, destination: "Notes", outcome: outcome)
    }

    /// The groups, rebuilt into a menu that has the anchor the Sleep row gives; what they are fed from is the test's own.
    private func groups(
        _ language: (bundle: Bundle, locale: Locale), waiting rows: [SessionRow] = [], terminals: [StandaloneTerminalSummary] = [], entries: [DictationEntry] = [], keepsText: Bool = true
    ) -> [NSMenuItem] {
        let suite = "status-groups-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let preferences = AppPreferences(defaults: defaults)
        preferences.dictationKeepText = keepsText
        let groups = StatusMenuGroups()
        (groups.bundle, groups.locale) = (language.bundle, language.locale)
        groups.terminals = { terminals }
        groups.seen = { SessionSeen() }
        groups.entries = { entries }
        groups.preferences = { preferences }
        groups.react(toSessions: rows)
        let menu = NSMenu()
        let anchor = NSMenuItem(title: "anchor", action: nil, keyEquivalent: "")
        anchor.tag = StatusMenuGroups.anchorTag
        menu.addItem(anchor)
        groups.rebuild(menu)
        return menu.items.filter { $0.tag != StatusMenuGroups.anchorTag }
    }

    private func titles(_ items: [NSMenuItem]) -> [String] { items.filter { $0.isSeparatorItem == false }.map(\.title) }

    @Test func theHeadersOfTheGroupsAgreeWithTheirCountInSpanish() {
        #expect(titles(groups(spanish)).first == "Sesiones" && titles(groups(spanish)).contains("Terminales"))
        #expect(titles(groups(spanish, waiting: waiting(1))).first == "Sesiones · 1 te necesita")
        #expect(titles(groups(spanish, waiting: waiting(2))).first == "Sesiones · 2 te necesitan")
        #expect(titles(groups(spanish, terminals: registry(terminals: 2))).contains("Terminales · 2"))
        #expect(titles(groups(spanish, terminals: registry(terminals: 1))).contains("Terminales · 1"))
    }

    @Test func theHeadersOfTheGroupsReadInEnglishAsBefore() {
        #expect(titles(groups(english)).first == "Sessions" && titles(groups(english)).contains("Terminals"))
        #expect(titles(groups(english, waiting: waiting(1))).first == "Sessions · 1 need you")
        #expect(titles(groups(english, waiting: waiting(3))).first == "Sessions · 3 need you")
        #expect(titles(groups(english, terminals: registry(terminals: 2))).contains("Terminals · 2"))
    }

    @Test func theEmptyRowsAndTheirNewRowsReadInBothLanguages() {
        let es = titles(groups(spanish))
        #expect(es.contains("No hay sesiones") && es.contains("Nueva sesión") && es.contains("No hay terminales") && es.contains("Nueva terminal"))
        let en = titles(groups(english))
        #expect(en.contains("No sessions") && en.contains("New session") && en.contains("No terminals") && en.contains("New terminal"))
    }

    /// A row with something at its right carries it in its title after three spaces, so a row is found by what its title starts with.
    private func row(_ items: [NSMenuItem], _ start: String) -> NSMenuItem? { items.first { $0.title.hasPrefix(start) } }

    @Test func theDictationRowsReadInSpanishWithTheAgeInSpanish() throws {
        let items = groups(spanish, entries: [entry(.pasted)])
        #expect(row(items, "Dictado")?.title == "Dictado" && row(items, "Dictar ahora") != nil)
        let last = try #require(row(items, "Copiar la última transcripción"))
        #expect(last.title.hasSuffix("hace 5 minutos"))
        let history = try #require(row(items, "Últimas transcripciones")?.submenu)
        #expect(history.items.count == 3 && history.items[0].title.hasPrefix("hello there") && history.items[0].title.hasSuffix("hace 5 minutos"))
        #expect(history.items[2].title == "Abrir historial…")
    }

    @Test func theDictationRowsReadInEnglishAsBefore() throws {
        let items = groups(english, entries: [entry(.copied)])
        #expect(row(items, "Dictation")?.title == "Dictation" && row(items, "Dictate now") != nil)
        let last = try #require(row(items, "Copy last transcript"))
        #expect(last.title.hasSuffix("5 minutes ago"))
        #expect(row(items, "Last transcripts")?.submenu?.items.last?.title == "Open history…")
    }

    @Test func aDictationThatKeepsNoTextSaysSoInBothLanguages() throws {
        let es = try #require(row(groups(spanish, keepsText: false), "Copiar la última transcripción"))
        #expect(es.title.hasSuffix("el texto no se guarda"))
        let en = try #require(row(groups(english, keepsText: false), "Copy last transcript"))
        #expect(en.title.hasSuffix("text is not kept"))
    }
}
