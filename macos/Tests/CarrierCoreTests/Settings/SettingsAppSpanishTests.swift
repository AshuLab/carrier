import Foundation
import Testing

@testable import CarrierCore

// The rest of Settings in Spanish (design/copy/es.json): the window and its sidebar, the General, Appearance, Notifications and Keybindings pages, the words the
// choices of the preferences give, the watched-repo notes and what VoiceOver reads for the log. English is asserted with `english` below and in the page tests.

private let b = spanish.bundle
private let l = spanish.locale

@Test func theSidebarNamesItsGroupsAndEveryPageInSpanish() {
    #expect(SettingsPage.Group.allCases.map { $0.heading(bundle: b, locale: l) } == [nil, "Espacio de trabajo", "Carrier", "Sistema"])
    #expect(SettingsPage.allCases.map { $0.title(bundle: b, locale: l) } == [
        "General", "Proveedores", "Apariencia", "Notificaciones", "Atajos de teclado", "Dictado", "Mantener despierto", "Chat", "Sesiones", "Proyectos", "Barra lateral",
        "Terminal", "Roles", "Vigilancia", "Comportamiento", "Motor", "Estado", "Acerca de",
    ])
    #expect(SettingsPage.general.detail(bundle: b, locale: l) == "La barra de menús y cómo se leen las horas")
    #expect(SettingsPage.keybindings.detail(bundle: b, locale: l) == "Las teclas que ejecutan las acciones de la app")
    #expect(SettingsPage.allCases.allSatisfy { $0.detail(bundle: b, locale: l).isEmpty == false })
}

@Test func thePagesAreFoundByTheirIdentifierWhateverTheLanguage() {
    for page in SettingsPage.allCases {
        #expect(SettingsPage(stored: page.rawValue) == page)
        // an earlier build stored the English title: that is still what opens the page, with the app in Spanish
        #expect(SettingsPage(stored: page.title(bundle: english.bundle, locale: english.locale)) == page)
    }
}

@Test func theGeneralPageIsInSpanish() {
    let page = generalPage(bundle: b, locale: l)
    #expect(page.menuBar == "Barra de menús" && page.display == "Visualización")
    #expect(page.iconStyle == PageRowText(title: "Estilo del icono", detail: "Lo que muestra el icono de la barra de menús"))
    #expect(page.animate.title == "Animar el icono" && page.listEpics.title == "Listar los epics en el menú")
    #expect(page.timeFormat.detail == "Los tiempos transcurridos se leen como \"11m\" o como una hora, \"14:32\"")
    #expect([page.relative, page.clockOption, page.system, page.hours12, page.hours24] == ["Relativo", "Reloj", "Sistema", "12 horas", "24 horas"])
}

@Test func theGeneralPageSaysTheSameEnglishAsBefore() {
    let page = generalPage(bundle: english.bundle, locale: english.locale)
    #expect(page.menuBar == "Menu bar" && page.display == "Display")
    #expect(page.iconStyle == PageRowText(title: "Icon style", detail: "What the icon in the menu bar shows"))
    #expect(page.animate.detail == "A segment moves over the bar while epics run, except in Low Power Mode")
    #expect(page.timeFormat.detail == "Ages read \"11m\" or as a time, \"14:32\"")
    #expect([page.relative, page.clockOption, page.system, page.hours12, page.hours24] == ["Relative", "Clock", "System", "12 hours", "24 hours"])
}

@Test func theAppearancePageQuotesTheCurrentNumbersInSpanish() {
    let page = appearancePage(textSize: 110, iconWeight: 1.25, codeSize: 13, bundle: b, locale: l)
    #expect([page.theme, page.look, page.color, page.code] == ["Tema", "Aspecto", "Color", "Código y salida"])
    #expect(page.textSize.detail == "El tamaño del texto de la interfaz, 110%; los mensajes tienen el suyo en Chat")
    #expect(page.textSizeValue == "110 por ciento")
    // the weight is written as the language writes numbers: a comma for Argentina
    #expect(page.iconWeight.detail == "Qué tan gruesos son los trazos de los iconos, 1,25" && page.iconWeightValue == "1,25")
    #expect(page.codeSizeValue == "13 puntos" && appearancePage(textSize: 100, iconWeight: 1, codeSize: 1, bundle: b, locale: l).codeSizeValue == "1 punto")
    #expect([page.stateWorking, page.stateNeedsAttention, page.stateReady, page.stateProblem] == ["Trabajando", "Requiere atención", "Listo para probar", "Un problema"])
    #expect(page.colorScheme.title == "Esquema de color" && page.accent.title == "Color de énfasis" && page.translucent.title == "Ventanas translúcidas")
    #expect(page.wrap.title == "Ajustar las líneas largas" && page.lineNumbers.detail == "En los bloques de código y en la salida de un comando")
    #expect(Copy.appearanceAccentName(theme: "Carrier", bundle: b, locale: l) == "Acento de Carrier")
}

@Test func theAppearancePageSaysTheSameEnglishAsBefore() {
    let page = appearancePage(textSize: 110, iconWeight: 1.25, codeSize: 13, bundle: english.bundle, locale: english.locale)
    #expect(page.textSize.detail == "The size of the text of the interface, 110%; the messages have their own in Chat")
    #expect(page.textSizeValue == "110 percent" && page.codeSizeValue == "13 points" && page.codeSize == "Code size")
    #expect(page.iconWeight.detail == "How thick the strokes of the icons are, 1.25" && page.iconWeightValue == "1.25")
    #expect(appearancePage(textSize: 100, iconWeight: 1, codeSize: 1, bundle: english.bundle, locale: english.locale).codeSizeValue == "1 point")
    #expect(page.iconSet.detail == "The look of the icons of the app: SF Symbols are the Mac's own")
    #expect([page.stateWorking, page.stateNeedsAttention, page.stateReady, page.stateProblem] == ["Working", "Needs attention", "Ready for test", "A problem"])
    #expect(Copy.appearanceAccentName(theme: "Carrier", bundle: english.bundle, locale: english.locale) == "Carrier accent")
}

@Test func theNotificationsPageIsInSpanish() {
    let page = notificationsPage(bundle: b, locale: l)
    #expect([page.groupCarrier, page.groupChat, page.groupDelivery, page.groupPermission] == ["Carrier", "Chat", "Entrega", "Permiso"])
    #expect(page.needsAttention == PageRowText(title: "Requiere atención", detail: "Un epic se detuvo y espera a una persona"))
    // the chat's switch has its own line and its own spoken label under the same title
    #expect(page.chatNeedsAttention == PageRowText(title: "Requiere atención", detail: "Una sesión espera una aprobación") && page.chatNeedsAttentionLabel == "El chat requiere atención")
    #expect(page.chatDone.title == "Terminado" && page.chatDoneLabel == "Chat terminado")
    #expect(page.remind.detail == "Mientras un epic o una sesión sigue necesitando atención. Listo para probar y Terminado nunca recuerdan")
    #expect(page.quiet.title == "Horas de silencio" && page.from.title == "Desde" && page.until.title == "Hasta")
    #expect([page.permission, page.checking, page.openSystemSettings, page.allow, page.sendTest] == ["Permiso del sistema", "Comprobando…", "Abrir Ajustes del Sistema", "Permitir", "Enviar una prueba"])
}

@Test func theNotificationsPageSaysTheSameEnglishAsBefore() {
    let page = notificationsPage(bundle: english.bundle, locale: english.locale)
    #expect(page.needsAttention == PageRowText(title: "Needs attention", detail: "An epic stopped and waits for a person"))
    #expect(page.chatNeedsAttention == PageRowText(title: "Needs attention", detail: "A session waits for an approval") && page.chatNeedsAttentionLabel == "Chat needs attention")
    #expect(page.dock.detail == "The Dock icon counts the epics that need a person and the sessions that wait for an approval")
    #expect(page.quiet.detail == "No banner and no sound: notifications wait in the Notification Center")
    #expect(page.checking == "Checking…" && page.openSystemSettings == "Open System Settings")
}

@Test func thePermissionAndTheReminderAreSaidInSpanish() {
    let banners = NotificationDelivery(style: .banners, soundOn: true)
    #expect(NotificationPermission.allowed(banners).text(bundle: b, locale: l) == "Permitido · banners · sonido activado")
    #expect(NotificationPermission.allowed(.init(style: .alerts, soundOn: false)).text(bundle: b, locale: l) == "Permitido · alertas · sonido desactivado")
    #expect(NotificationPermission.allowed(.init(style: .none, soundOn: true)).text(bundle: b, locale: l) == "Permitido · notificaciones en Ninguna")
    #expect(NotificationPermission.denied.text(bundle: b, locale: l) == "Denegado en Ajustes del Sistema")
    #expect(NotificationPermission.notAsked.text(bundle: b, locale: l) == "Aún no se pidió · la primera notificación lo pide")
    #expect(NotificationPermission.noBundle.text(bundle: b, locale: l) == "Solo disponible desde Carrier.app")
    #expect(NotificationPermission.denied.testAdvice(bundle: b, locale: l) == "Las notificaciones de Carrier están desactivadas en Ajustes del Sistema.")
    #expect(NotificationPermission.allowed(.init(style: .none, soundOn: false)).testAdvice(bundle: b, locale: l) == "Las notificaciones de Carrier están en Ninguna en Ajustes del Sistema.")
    #expect(NotificationPermission.allowed(banners).testAdvice(bundle: b, locale: l) == nil)
    #expect(ReminderInterval.allCases.map { $0.title(bundle: b, locale: l) } == ["Nunca", "Después de 15 minutos", "Después de una hora"])
    #expect(ReminderInterval.allCases.map { $0.title(bundle: english.bundle, locale: english.locale) } == ["Never", "After 15 minutes", "After an hour"])
}

@Test func aShortcutRowSaysItsKeysItsDefaultAndWhatFlagsItInSpanish() {
    let combo = KeyCombo(key: "k", modifiers: .command)
    let plain = shortcutRowText(command: .newSession, combo: combo, clash: nil, refused: nil, recording: false, bundle: b, locale: l)
    #expect(plain.keys == "⌘K" && plain.value == "⌘K" && plain.warning == nil)
    #expect(plain.detail == "Predeterminado: \(ShortcutCommand.newSession.defaultCombo!.text)" && plain.defaultButton == "Predeterminado")
    #expect(plain.label == "Atajo de Nueva sesión" && plain.backToDefault == "Volver al predeterminado de Nueva sesión")
    let waiting = shortcutRowText(command: .newSession, combo: nil, clash: nil, refused: nil, recording: true, bundle: b, locale: l)
    #expect(waiting.keys == "Presiona las teclas…" && waiting.value == "Ninguno")
    #expect(shortcutRowText(command: .newSession, combo: nil, clash: nil, refused: nil, recording: false, bundle: b, locale: l).keys == "Ninguno")
    #expect(shortcutRowText(command: .home, combo: combo, clash: .search, refused: nil, recording: false, bundle: b, locale: l).warning == "También Buscar")
    #expect(shortcutRowText(command: .home, combo: combo, clash: .search, refused: combo, recording: false, bundle: b, locale: l).warning == "⌘K es del sistema")
}

@Test func aShortcutRowSaysTheSameEnglishAsBefore() {
    let combo = KeyCombo(key: "k", modifiers: .command)
    let row = shortcutRowText(command: .newSession, combo: combo, clash: .search, refused: nil, recording: false, bundle: english.bundle, locale: english.locale)
    #expect(row.keys == "⌘K" && row.warning == "Also Search" && row.defaultButton == "Default")
    #expect(row.detail == "Default: \(ShortcutCommand.newSession.defaultCombo!.text)" && row.label == "Shortcut for New session" && row.backToDefault == "Back to the default for New session")
    #expect(shortcutRowText(command: .newSession, combo: nil, clash: nil, refused: nil, recording: true, bundle: english.bundle, locale: english.locale).keys == "Press the keys…")
    #expect(shortcutRowText(command: .newSession, combo: nil, clash: nil, refused: nil, recording: false, bundle: english.bundle, locale: english.locale).value == "None")
    #expect(shortcutRowText(command: .home, combo: combo, clash: nil, refused: combo, recording: false, bundle: english.bundle, locale: english.locale).warning == "⌘K is the system's")
}

@Test func theWordsTheChoicesOfThePreferencesGiveAreSpanish() {
    #expect(WorkIn.allCases.map { $0.title(bundle: b, locale: l) } == ["La carpeta base", "Un worktree nuevo"])
    #expect(ColorSchemeChoice.allCases.map { $0.title(bundle: b, locale: l) } == ["Sistema", "Claro", "Oscuro"])
    #expect(Density.allCases.map { $0.title(bundle: b, locale: l) } == ["Compacta", "Cómoda"])
    #expect(ChatLineSpacing.allCases.map { $0.title(bundle: b, locale: l) } == ["Ajustado", "Normal", "Holgado"])
    #expect(MessageSpacing.allCases.map { $0.title(bundle: b, locale: l) } == ["Compacto", "Cómodo", "Amplio"])
    #expect(MessageWidth.allCases.map { $0.title(bundle: b, locale: l) } == ["Angosto", "Medio", "Ancho", "Ultra ancho", "El más ancho"])
    #expect(ChatSurface.allCases.map { $0.title(bundle: b, locale: l) } == ["Vidrio", "Plano"])
    #expect(MessageTimes.allCases.map { $0.title(bundle: b, locale: l) } == ["Nunca", "Al pasar el cursor", "Siempre"])
    #expect(ToolOutputMode.allCases.map { $0.title(bundle: b, locale: l) } == ["Oculto", "Contraído", "Expandido"])
    #expect(DiffStyle.allCases.map { $0.title(bundle: b, locale: l) } == ["Unificado", "Dividido"])
    #expect(OutputLength.allCases.map { $0.title(bundle: b, locale: l) } == ["20 líneas", "50 líneas", "100 líneas"])
}

@Test func theWordsTheChoicesOfThePreferencesGiveSayTheSameEnglishAsBefore() {
    let e = english
    #expect(WorkIn.allCases.map { $0.title(bundle: e.bundle, locale: e.locale) } == ["The base folder", "A new worktree"])
    #expect(ColorSchemeChoice.allCases.map { $0.title(bundle: e.bundle, locale: e.locale) } == ["System", "Light", "Dark"])
    #expect(Density.allCases.map { $0.title(bundle: e.bundle, locale: e.locale) } == ["Compact", "Comfortable"])
    #expect(ChatLineSpacing.allCases.map { $0.title(bundle: e.bundle, locale: e.locale) } == ["Tight", "Normal", "Loose"])
    #expect(MessageSpacing.allCases.map { $0.title(bundle: e.bundle, locale: e.locale) } == ["Compact", "Comfortable", "Spacious"])
    #expect(MessageWidth.allCases.map { $0.title(bundle: e.bundle, locale: e.locale) } == ["Narrow", "Medium", "Wide", "Ultra wide", "Widest"])
    #expect(ChatSurface.allCases.map { $0.title(bundle: e.bundle, locale: e.locale) } == ["Glass", "Flat"])
    #expect(MessageTimes.allCases.map { $0.title(bundle: e.bundle, locale: e.locale) } == ["Never", "On hover", "Always"])
    #expect(ToolOutputMode.allCases.map { $0.title(bundle: e.bundle, locale: e.locale) } == ["Hidden", "Collapsed", "Expanded"])
    #expect(DiffStyle.allCases.map { $0.title(bundle: e.bundle, locale: e.locale) } == ["Unified", "Split"])
    #expect(OutputLength.allCases.map { $0.title(bundle: e.bundle, locale: e.locale) } == ["20 lines", "50 lines", "100 lines"])
}

@Test func theWindowSaysItsWordsInSpanish() {
    #expect(Copy.settingsWindowTitle(bundle: b, locale: l) == "Ajustes" && Copy.settingsSearchPrompt(bundle: b, locale: l) == "Buscar ajustes")
    #expect(Copy.settingsBack(bundle: b, locale: l) == "Atrás" && Copy.settingsForward(bundle: b, locale: l) == "Adelante")
    #expect(Copy.settingsPageActions(bundle: b, locale: l) == "Acciones de la página" && Copy.settingsResetMenu(bundle: b, locale: l) == "Restablecer esta página…")
    #expect(Copy.settingsResetTitle(page: "Apariencia", bundle: b, locale: l) == "¿Restablecer Apariencia?")
    #expect(Copy.settingsResetCancel(bundle: b, locale: l) == "Cancelar" && Copy.settingsResetConfirm(bundle: b, locale: l) == "Restablecer")
    #expect(Copy.settingsResetMessage(bundle: b, locale: l) == "Todos los ajustes de esta página vuelven a como venían. Esto no se puede deshacer.")
    #expect(Copy.settingsCopy(bundle: b, locale: l) == "Copiar")
}

@Test func theWindowSaysTheSameEnglishAsBefore() {
    let e = english
    #expect(Copy.settingsWindowTitle(bundle: e.bundle, locale: e.locale) == "Settings" && Copy.settingsSearchPrompt(bundle: e.bundle, locale: e.locale) == "Search settings")
    #expect(Copy.settingsResetTitle(page: "Appearance", bundle: e.bundle, locale: e.locale) == "Reset Appearance?")
    #expect(Copy.settingsResetMessage(bundle: e.bundle, locale: e.locale) == "Every setting on this page goes back to how it came. This can’t be undone.")
    #expect(Copy.settingsResetMenu(bundle: e.bundle, locale: e.locale) == "Reset this page…" && Copy.settingsPageActions(bundle: e.bundle, locale: e.locale) == "Page actions")
    #expect(SettingsPage.allCases.map { $0.title(bundle: e.bundle, locale: e.locale) } == [
        "General", "Providers", "Appearance", "Notifications", "Keybindings", "Dictation", "Keep awake", "Chat", "Sessions", "Projects", "Sidebar", "Terminal", "Roles", "Watching",
        "Behavior", "Engine", "Health", "About",
    ])
}

@Test func theNoteOfAWatchedRepoIsSpanish() throws {
    let state = ConnectionState.running(try decodeSnapshot(Data(contentsOf: testPaths().fixtures.appendingPathComponent("snapshot.json"))))
    #expect(settingsNote(state: state, canReload: true, outcome: nil, bundle: b, locale: l) == "Carrier aplica este repositorio al próximo epic")
    #expect(settingsNote(state: state, canReload: false, outcome: .nobody, repo: "a/b", bundle: b, locale: l) == "Carrier lee a/b cuando arranca")
    #expect(settingsNote(state: state, canReload: true, outcome: .refused(.words("x")), bundle: b, locale: l) == "Sin usar: Carrier conservó su configuración anterior")
    #expect(settingsNote(state: state, canReload: true, outcome: .noAnswer, repo: "a/b", bundle: b, locale: l) == "Carrier no respondió: puede que no haya aplicado a/b")
    #expect(addedRepoNote("a/b", outcome: .applied, bundle: b, locale: l) == (text: "Carrier aplica a/b al próximo epic", failed: false))
    #expect(addedRepoNote("a/b", outcome: .noAnswer, bundle: b, locale: l) == (text: "a/b se agregó a la lista de Carrier, pero Carrier no respondió: puede que no lo haya aplicado.", failed: true))
    let refused = addedRepoNote("a/b", outcome: .refused(.words("malo")), bundle: b, locale: l)
    #expect(refused.failed && refused.text == "a/b se agregó a la lista de Carrier, pero Carrier conservó su configuración: malo")
}

@Test func thePullRequestARunPublishedIsSaidInSpanish() {
    #expect(publishedNote("created 946 (main)", bundle: b, locale: l) == PublishedNote(verb: "Creado", number: 946, identifier: "946", branch: "main"))
    #expect(["pushed 1", "updated 1", "published 1", "merged 1", "closed 1"].compactMap { publishedNote($0, bundle: b, locale: l)?.verb } == ["Enviado a", "Actualizado", "Publicado", "Fusionado", "Cerrado"])
    #expect(publishedNote("deleted 5 (main)", bundle: b, locale: l) == nil)
}

@Test func whatVoiceOverReadsForTheLogIsSpanish() {
    #expect(spokenDuration(725, bundle: b, locale: l) == "725 milisegundos" && spokenDuration(1, bundle: b, locale: l) == "1 milisegundo")
    #expect(spokenDuration(2000, bundle: b, locale: l) == "2 segundos" && spokenDuration(1000, bundle: b, locale: l) == "1 segundo")
    // a fraction is written with the language's own separator
    #expect(spokenDuration(5240, bundle: b, locale: l) == "5,2 segundos")
    #expect(spokenDuration(125_000, bundle: b, locale: l) == "2 minutos 5 segundos" && spokenDuration(59_990, bundle: b, locale: l) == "1 minuto")
    #expect(spokenDuration(3_780_000, bundle: b, locale: l) == "1 hora 3 minutos")
    var call = ToolCall(start: ChatEvent(id: 1, at: 1000, kind: "tool_start", callId: "c", tool: "Skill", arg: "solve:ship"))
    call.status = .failed
    call.endedAt = 1725
    #expect(callAccessibilityLabel(call, bundle: b, locale: l) == "solve:ship, falló, 725 milisegundos")
    call.status = .ok
    #expect(callAccessibilityLabel(call, bundle: b, locale: l) == "solve:ship, correcta, 725 milisegundos")
    call.status = .running
    #expect(callAccessibilityLabel(call, bundle: b, locale: l) == "solve:ship, en ejecución")
    let done = resultCard(SessionResult(outcome: "completed", summary: "s", verification: .init(ci: "passed", evidence: "e"), reason: nil), bundle: b, locale: l)!
    #expect(resultAccessibilityLabel(done, open: true, bundle: b, locale: l).hasSuffix(", CI correcta, abierto"))
    #expect(resultAccessibilityLabel(done, open: false, bundle: b, locale: l).hasSuffix(", CI correcta, cerrado"))
}
