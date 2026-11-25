import Foundation
import Testing

@testable import CarrierCore

// The Terminal area in Spanish (design/copy/es.json): each pure function that builds a sentence says its Spanish words, and every plural and select it uses has a
// Spanish case asserted, `one` included. The English words are asserted in the other files of this folder and in CarrierTerminalStoreTests, with `english`.
// Numbers are said in Argentina's locale, whose decimals take a comma.

private let b = spanish.bundle
private let l = spanish.locale

private func process(_ title: String, _ commands: [String]) -> TerminalActiveProcess {
    TerminalActiveProcess(paneId: UUID(), paneTitle: title, commands: commands)
}

private func ask(
    _ target: TerminalCloseTarget, _ running: [TerminalActiveProcess], title: String? = nil, kind: SessionRemovalKind? = nil, error: String? = nil
) -> Question {
    terminalConfirmationQuestion(for: target, running: running, targetTitle: title, removalKind: kind, inspectionError: error, bundle: b, locale: l)
}

// MARK: the tabs, the panes and the lists

@Test func aTabWithNoPaneToNameItIsCalledTerminalInSpanish() {
    let empty = TerminalTab(owner: .terminal(UUID()), root: .leaf(UUID()), panes: [:], activePaneId: UUID())
    #expect(empty.title(bundle: b, locale: l) == "Terminal")
    let named = TerminalTab(owner: .terminal(UUID()), spec: TerminalLaunchSpec(workingDirectory: "/tmp/api", title: "zsh"))
    #expect(named.title(bundle: b, locale: l) == "zsh")
    let untitled = TerminalTab(owner: .terminal(UUID()), spec: TerminalLaunchSpec(workingDirectory: "/tmp/api"))
    #expect(untitled.title(bundle: b, locale: l) == "api")
    #expect(untitled.activePane?.displayTitle(bundle: b, locale: l) == "api")
}

@Test func theSubtitleOfTheTerminalsIsSaidInSpanishWithItsPlural() {
    #expect(terminalsSubtitle(count: 0, bundle: b, locale: l) == "Sin terminales")
    #expect(terminalsSubtitle(count: 1, bundle: b, locale: l) == "1 terminal")
    #expect(terminalsSubtitle(count: 3, bundle: b, locale: l) == "3 terminales")
    #expect(Copy.terminalCount(count: 1, bundle: b, locale: l) == "1 terminal")
    #expect(Copy.terminalCount(count: 4, bundle: b, locale: l) == "4 terminales")
}

@Test func aTerminalSaysItsTabsAndPanesInSpanishWithTheirPlurals() {
    var registry = TerminalRegistry()
    let first = UUID()
    let second = UUID()
    _ = registry.openTab(owner: .terminal(first), spec: TerminalLaunchSpec(workingDirectory: "/existing/api", customTitle: "API"))
    let logs = registry.openTab(owner: .terminal(first), spec: TerminalLaunchSpec(workingDirectory: "/existing/api/logs", title: "Logs"))
    _ = registry.splitPane(logs.activePaneId, edge: .trailing)
    let web = registry.openTab(owner: .terminal(second), spec: TerminalLaunchSpec(workingDirectory: "/existing/web", title: "Web"))
    _ = registry.splitPane(web.activePaneId, edge: .trailing)
    let third = UUID()
    _ = registry.openTab(owner: .terminal(third), spec: TerminalLaunchSpec(workingDirectory: "/existing/solo"))
    _ = registry.openTab(owner: .terminal(third), spec: TerminalLaunchSpec(workingDirectory: "/existing/solo"))

    let summaries = registry.standaloneTerminals()
    #expect(summaries[0].countsSummary(bundle: b, locale: l) == "2 pestañas · 3 paneles")
    #expect(summaries[0].subtitle(home: "/existing", bundle: b, locale: l) == "~/api/logs · 2 pestañas · 3 paneles")
    #expect(summaries[1].countsSummary(bundle: b, locale: l) == "2 paneles")
    #expect(summaries[2].countsSummary(bundle: b, locale: l) == "2 pestañas")
    #expect(Copy.terminalTabsCount(count: 1, bundle: b, locale: l) == "1 pestaña")
    #expect(Copy.terminalPanesCount(count: 1, bundle: b, locale: l) == "1 panel")
    #expect(filteredStandaloneTerminals(summaries, query: "web", bundle: b, locale: l).map(\.id) == [second])
}

// MARK: the Terminal page of Settings

@Test func theTitlesTheSettingsGiveAreSaidInSpanish() {
    #expect(TerminalCursorStyleChoice.allCases.map { $0.title(bundle: b, locale: l) } == ["Bloque", "Barra", "Subrayado"])
    #expect(TerminalOptionAsAlt.allCases.map { $0.title(bundle: b, locale: l) } == ["Desactivado", "Option izquierda", "Option derecha", "Ambas"])
    #expect(TerminalScrollbackLimit.allCases.map { $0.title(bundle: b, locale: l) } == ["1 MB", "10 MB", "50 MB", "100 MB"])
    #expect(TerminalSettings.minimumContrastLabel(1.0, bundle: b, locale: l) == "Desactivado · 1,0 : 1")
    #expect(TerminalSettings.minimumContrastLabel(4.5, bundle: b, locale: l) == "4,5 : 1")
}

@Test func theValuesOfTheSettingsRowsAreSaidInSpanish() {
    #expect(Copy.terminalOn(bundle: b, locale: l) == "Activado" && Copy.terminalOff(bundle: b, locale: l) == "Desactivado")
    #expect(Copy.terminalPoints(size: 13, bundle: b, locale: l) == "13 pt")
    #expect(Copy.terminalSameAsApp(theme: "Ocean", bundle: b, locale: l) == "Igual que la app (Ocean)")
    #expect(Copy.terminalSameAsAppearance(value: "Menlo", bundle: b, locale: l) == "Igual que Apariencia (Menlo)")
    #expect(Copy.terminalSettingsContrastDetail(contrast: "3,0 : 1", bundle: b, locale: l) == "Realza el texto ANSI de poco contraste · 3,0 : 1")
    #expect(Copy.terminalSettingsPaddingXDetail(size: 10, bundle: b, locale: l) == "Margen izquierdo y derecho dentro de cada panel · 10 pt")
    #expect(Copy.terminalSettingsPaddingYDetail(size: 8, bundle: b, locale: l) == "Margen superior e inferior dentro de cada panel · 8 pt")
    #expect(Copy.terminalPointsValue(count: 1, bundle: b, locale: l) == "1 punto")
    #expect(Copy.terminalPointsValue(count: 10, bundle: b, locale: l) == "10 puntos")
    #expect(Copy.terminalPercentValue(percent: 50, bundle: b, locale: l) == "50 por ciento")
}

// MARK: Continue in Terminal

@Test func theCommandOfContinueInTerminalPrintsItsTwoSentencesInSpanish() {
    let resume = ValidResume(harness: "claude", sessionId: "abc", cwd: "/tmp", configDir: nil)
    let spanishLaunch = embeddedResumeLaunch(resume, bundle: b, locale: l)
    #expect(spanishLaunch.command.contains(#"\nContinuar en Terminal terminó con el estado %s."#))
    #expect(spanishLaunch.command.contains(" Pulsa Retorno para cerrar..."))
    #expect(spanishLaunch.command.contains("Continue in Terminal exited") == false)
    let englishLaunch = embeddedResumeLaunch(resume, bundle: english.bundle, locale: english.locale)
    #expect(englishLaunch.command.contains(#"\nContinue in Terminal exited with status %s."#) && englishLaunch.command.contains(" Press Return to close..."))
    #expect(Copy.terminalContinueExited(status: "1", bundle: b, locale: l) == "Continuar en Terminal terminó con el estado 1.")
}

// MARK: the confirmations

@Test func aPaneAsksBeforeClosingInSpanish() {
    let one = ask(.pane(UUID()), [process("Dev server", ["vite"])])
    #expect(one == Question(title: "¿Cerrar «Dev server»?", message: "Aún se está ejecutando un comando: vite. Cerrar esta terminal finalizará el comando.", confirm: "Cerrar"))
    let two = ask(.pane(UUID()), [process("Dev server", ["vitest", "vite"])])
    #expect(two.message == "Comandos aún en ejecución: vite, vitest. Cerrar esta terminal finalizará los comandos.")
    let unverified = ask(.pane(UUID()), [], error: "ps failed")
    #expect(unverified == Question(title: "¿Cerrar la terminal?", message: "No se pudieron verificar los comandos en ejecución. Cerrar esta terminal puede finalizar un comando activo.", confirm: "Cerrar"))
    let still = ask(.pane(UUID()), [])
    #expect(still.message == "Aún se está ejecutando un comando en esta terminal. Cerrar esta terminal lo finalizará.")
}

@Test func aTabAsksBeforeClosingInSpanishWithItsPlural() {
    let one = ask(.tab(UUID()), [process("Dev server", ["vite"])], title: "Dev")
    #expect(one == Question(title: "¿Cerrar la pestaña «Dev»?", message: "Aún se está ejecutando un comando: vite. Cerrar esta pestaña finalizará el comando.", confirm: "Cerrar"))
    let many = ask(.tab(UUID()), [process("a", ["x"]), process("b", ["y"])], title: "Dev")
    #expect(many.title == "¿Cerrar la pestaña «Dev» con 2 terminales en ejecución?")
    #expect(ask(.tab(UUID()), [process("a", ["x"]), process("b", ["y"])]).title == "¿Cerrar la pestaña con 2 terminales en ejecución?")
    let unverified = ask(.tab(UUID()), [], error: "ps failed")
    #expect(unverified == Question(title: "¿Cerrar la pestaña?", message: "No se pudieron verificar los comandos en ejecución. Cerrar esta pestaña puede finalizar comandos activos.", confirm: "Cerrar"))
    // the one of the plural, which a tab never reaches with a count of 1 but the catalog holds
    #expect(Copy.terminalConfirmTabTitleMany(count: 1, bundle: b, locale: l) == "¿Cerrar la pestaña con 1 terminal en ejecución?")
    #expect(Copy.terminalConfirmTabTitleNamedMany(count: 1, name: "Dev", bundle: b, locale: l) == "¿Cerrar la pestaña «Dev» con 1 terminal en ejecución?")
}

@Test func aSessionRemovalAsksBeforeClosingItsTerminalsInSpanish() {
    let archive = ask(.owners([.session("s")]), [process("Dev server", ["a", "b", "c", "d", "e"])], kind: .archive)
    #expect(archive == Question(
        title: "¿Archivar la sesión con la terminal en ejecución «Dev server»?",
        message: "Comandos aún en ejecución: a, b, c y 2 más. Archivar esta sesión cerrará su terminal y finalizará los comandos.",
        confirm: "Archivar"
    ))
    let delete = ask(.owners([.session("s"), .session("t")]), [process("a", ["x"]), process("b", ["y"])], kind: .delete)
    #expect(delete == Question(
        title: "¿Eliminar la sesión con 2 terminales en ejecución?",
        message: "Comandos aún en ejecución: x, y. Eliminar estas sesiones cerrará sus terminales y finalizará los comandos.",
        confirm: "Eliminar"
    ))
    let clear = ask(.owners([.session("s")]), [process("a", ["vite"])], kind: .clear)
    #expect(clear == Question(
        title: "¿Eliminar las sesiones archivadas con una terminal en ejecución?",
        message: "Aún se está ejecutando un comando: vite. Eliminar estas sesiones cerrará sus terminales y finalizará el comando.",
        confirm: "Eliminar todas"
    ))
    let clearNone = ask(.owners([.session("s")]), [], kind: .clear, error: "x")
    #expect(clearNone.title == "¿Eliminar las sesiones archivadas?")
    #expect(clearNone.message == "No se pudieron verificar los comandos en ejecución. Eliminar estas sesiones cerrará sus terminales y puede finalizar comandos activos.")
    let close = ask(.owner(.session("s")), [process("a", ["vite"])])
    #expect(close == Question(
        title: "¿Cerrar la terminal de la sesión con la terminal en ejecución «a»?",
        message: "Aún se está ejecutando un comando: vite. Cerrar su terminal finalizará el comando.",
        confirm: "Cerrar"
    ))
    let closeMany = ask(.owner(.session("s")), [process("a", ["x"]), process("b", ["y"])])
    #expect(closeMany.title == "¿Cerrar las terminales de la sesión con 2 terminales en ejecución?")
    #expect(closeMany.message == "Comandos aún en ejecución: x, y. Cerrar sus terminales finalizará los comandos.")
    let unverified = ask(.owner(.session("s")), [], error: "x")
    #expect(unverified.title == "¿Cerrar la terminal de la sesión?")
    #expect(unverified.message == "No se pudieron verificar los comandos en ejecución. Cerrar sus terminales puede finalizar comandos activos.")
    let archiveUnverified = ask(.owners([.session("s")]), [], kind: .archive, error: "x")
    #expect(archiveUnverified.title == "¿Archivar la sesión?")
    #expect(archiveUnverified.message == "No se pudieron verificar los comandos en ejecución. Archivar esta sesión cerrará sus terminales y puede finalizar comandos activos.")
    let deleteUnverified = ask(.owners([.session("s")]), [], kind: .delete, error: "x")
    #expect(deleteUnverified.message == "No se pudieron verificar los comandos en ejecución. Eliminar esta sesión cerrará sus terminales y puede finalizar comandos activos.")
    // the one of the plurals the owners' sentences use
    #expect(Copy.terminalConfirmTerminals(count: 1, bundle: b, locale: l) == "su terminal")
    #expect(Copy.terminalConfirmTerminals(count: 2, bundle: b, locale: l) == "sus terminales")
    #expect(Copy.terminalConfirmOwnerTitleMany(count: 1, prefix: "Archivar la sesión", bundle: b, locale: l) == "¿Archivar la sesión con 1 terminal en ejecución?")
    #expect(Copy.terminalConfirmOwnerTitleOne(prefix: "Archivar la sesión", bundle: b, locale: l) == "¿Archivar la sesión con una terminal en ejecución?")
}

@Test func quittingAsksBeforeClosingTheTerminalsInSpanishWithItsPlural() {
    let unverified = ask(.all, [], error: "ps failed")
    #expect(unverified == Question(title: "¿Salir de Carrier?", message: "No se pudieron verificar los comandos en ejecución. Salir de Carrier puede finalizar comandos activos.", confirm: "Salir"))
    let one = ask(.all, [process("Dev server", ["vite"])])
    #expect(one == Question(title: "¿Salir de Carrier con la terminal en ejecución «Dev server»?", message: "Aún se está ejecutando un comando: vite. Salir de Carrier finalizará el comando.", confirm: "Salir"))
    let many = ask(.all, [process("a", ["x"]), process("b", ["y"]), process("c", ["z"])])
    #expect(many.title == "¿Salir de Carrier con 3 terminales en ejecución?")
    #expect(many.message == "Comandos aún en ejecución: x, y, z. Salir de Carrier finalizará los comandos.")
    #expect(Copy.terminalConfirmQuitTitleMany(count: 1, bundle: b, locale: l) == "¿Salir de Carrier con 1 terminal en ejecución?")
    #expect(Copy.terminalConfirmQuitTitleOne(bundle: b, locale: l) == "¿Salir de Carrier con una terminal en ejecución?")
}

@Test func theCommandsStillRunningAreSaidInSpanishWithTheirPluralAndSelect() {
    #expect(Copy.terminalConfirmSummaryMore(commands: "a, b, c", count: 1, bundle: b, locale: l) == "Comandos aún en ejecución: a, b, c y 1 más.")
    #expect(Copy.terminalConfirmSummaryMore(commands: "a, b, c", count: 4, bundle: b, locale: l) == "Comandos aún en ejecución: a, b, c y 4 más.")
    #expect(Copy.terminalConfirmWhat(which: .it, bundle: b, locale: l) == "el comando")
    #expect(Copy.terminalConfirmWhat(which: .them, bundle: b, locale: l) == "los comandos")
    #expect(Copy.terminalConfirmWhat(which: .other, bundle: b, locale: l) == "los comandos activos")
    #expect(Copy.terminalConfirmSessions(which: .many, bundle: b, locale: l) == "estas sesiones")
    #expect(Copy.terminalConfirmSessions(which: .other, bundle: b, locale: l) == "esta sesión")
}

// MARK: the words the views call straight from Copy

@Test func everyTerminalKeyWithNoArgumentIsInTheSpanishCatalogWithItsSpanishWords() throws {
    let file = testPaths().root.appendingPathComponent("design/copy/es.json")
    let words = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: String])
    let plain = words.filter { key, value in key.hasPrefix("terminal") && value.contains("{") == false }
    #expect(plain.count > 70)
    for (key, value) in plain {
        #expect(b.localizedString(forKey: key, value: "missing", table: nil) == value, Comment(rawValue: key))
    }
}

@Test func theWordsWithArgumentsTheTerminalViewsCallAreSpanishWithTheirPluralsAndSelects() {
    #expect(Copy.terminalCloseNamed(title: "api", bundle: b, locale: l) == "Cerrar api")
    #expect(Copy.terminalAddTabIn(folder: "~/api", bundle: b, locale: l) == "Añadir pestaña en ~/api")
    #expect(Copy.terminalRowHelp(title: "api", folder: "/p/api", bundle: b, locale: l) == "api\n/p/api")
    #expect(Copy.terminalRowLabel(title: "api", subtitle: "~/api", bundle: b, locale: l) == "api, ~/api")
    #expect(Copy.terminalTabWithPanes(title: "api", count: 1, bundle: b, locale: l) == "api, 1 panel")
    #expect(Copy.terminalTabWithPanes(title: "api", count: 3, bundle: b, locale: l) == "api, 3 paneles")
    #expect(Copy.terminalTabHelpWithPanes(title: "api", count: 1, folder: "~/api", bundle: b, locale: l) == "api · 1 panel\n~/api")
    #expect(Copy.terminalTabHelpWithPanes(title: "api", count: 2, folder: "~/api", bundle: b, locale: l) == "api · 2 paneles\n~/api")
    #expect(Copy.terminalPaneDragHelp(title: "api", folder: "~/api", bundle: b, locale: l) == "api (~/api) — Arrastra para mover o intercambiar el panel")
    #expect(Copy.terminalPaneDragLabel(title: "api", bundle: b, locale: l) == "Mover el panel api")
    #expect(Copy.terminalPaneValue(which: .active, bundle: b, locale: l) == "Panel activo")
    #expect(Copy.terminalPaneValue(which: .other, bundle: b, locale: l) == "Panel")
    #expect(Copy.terminalContinueHelp(agent: "Claude", command: "cd x", bundle: b, locale: l).hasPrefix("Abre el panel de la terminal de abajo en la carpeta donde empezó y reanuda Claude"))
    #expect(Copy.terminalCursorStyle(style: .other, bundle: b, locale: l) == "Subrayado")
}
