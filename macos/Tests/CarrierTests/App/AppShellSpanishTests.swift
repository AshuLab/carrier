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
            "Inicio", "Sesiones", "Carrier", "Archivo", "Atrás", "Adelante", "Mostrar u ocultar la barra lateral", "Mostrar u ocultar el inspector", "Entrar en pantalla completa",
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
        #expect(sleep.submenu?.items.filter { $0.isSeparatorItem == false }.map(\.title).suffix(2) == ["Mantener despierto durante", "Ajustes de mantener despierto…"])
    }

    @Test func theStatusMenuRowsOpenInTheLanguageOfTheApp() {
        let status = WindowController.shared
        let menu = NSMenu()
        status.addMenuItem(to: menu, bundle: spanish.bundle, locale: spanish.locale)
        status.addSettingsItem(to: menu, bundle: spanish.bundle, locale: spanish.locale)
        status.addAboutItem(to: menu, bundle: spanish.bundle, locale: spanish.locale)
        #expect(menu.items.map(\.title) == ["Abrir ventana", "Ajustes…", "Acerca de Carrier"])
    }
}
