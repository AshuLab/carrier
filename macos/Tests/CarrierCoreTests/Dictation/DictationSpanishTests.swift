import Foundation
import Testing

@testable import CarrierCore

// The Dictation area in Spanish (design/copy/es.json): each pure function that builds a sentence says its Spanish words, and every plural and select it
// uses has a Spanish case asserted, `one` included. The English words are asserted in the other files of this folder, with `english`.
// Numbers are said in Argentina's locale, whose thousands take a dot and whose decimals a comma.

private let b = spanish.bundle
private let l = spanish.locale

private func model(_ id: String, _ recognizer: RecognizerID, bytes: Int64? = 500_000_000, languages: Set<String> = ["en"], detects: Bool = false, partial: PartialText = .native) -> SpeechModel {
    SpeechModel(
        id: id, recognizer: recognizer, name: id, bytes: bytes, languages: languages, detectsLanguage: detects, partial: partial, licence: "MIT",
        card: URL(string: "https://huggingface.co/x")!
    )
}

private var spanishCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.locale = Locale(identifier: "es_AR")
    return calendar
}

/// 2023-11-14 12:00 UTC, a Tuesday.
private let now = Date(timeIntervalSince1970: 1_699_963_200)

private func count(daysAgo: Int, words: Int, dictations: Int = 1, seconds: Double = 10, hour: Int = 9) -> DictationCount {
    let day = dictationDayKey(now.addingTimeInterval(-Double(daysAgo) * 86400), calendar: spanishCalendar)
    return DictationCount(day: day, hour: hour, model: "Apple", dictations: dictations, words: words, seconds: seconds, longest: seconds)
}

// MARK: the microphone of the message box

@Test func theMicrophoneOfTheBoxSaysEachStateInSpanish() throws {
    func box(_ state: DictationSession.State, _ microphone: MicrophonePermission = .allowed, ready: Bool = true, slow: Bool = false) throws -> DictationPresentation {
        try #require(dictationPresentation(state, registered: true, microphone: microphone, modelReady: ready, answerIsSlow: slow, bundle: b, locale: l))
    }
    let idle = try box(.idle)
    #expect(idle.label == "Dictar" && idle.help == "Dictar" && idle.caption == nil)
    let blocked = try box(.idle, .denied)
    #expect(blocked.label == "El dictado está bloqueado" && blocked.help == "Micrófono bloqueado")
    let preparing = try box(.gettingReady)
    #expect(preparing.label == "El dictado se está preparando" && preparing.caption == "Preparando el modelo…" && preparing.help == "Preparando el modelo…")
    let listening = try box(.listening)
    #expect(listening.label == "Detener el dictado" && listening.help == "Detener el dictado" && listening.caption == nil)
    #expect(try box(.listening, ready: false).caption == "Preparando el modelo…")
    let transcribing = try box(.transcribing)
    #expect(transcribing.label == "Transcribiendo" && transcribing.help == "Transcribiendo…" && transcribing.caption == nil)
    #expect(try box(.transcribing, slow: true).caption == "Transcribiendo…")
    let cleaning = try box(.cleaning)
    #expect(cleaning.label == "Limpiando, pulsa para omitir" && cleaning.help == "Limpiando… Haz clic para omitir" && cleaning.caption == "Limpiando…")
}

@Test func theBlockedMicrophonePopoverIsSaidInSpanish() {
    #expect(MicrophoneBlockedPopover.title(bundle: b, locale: l) == "Carrier no puede usar el micrófono")
    #expect(MicrophoneBlockedPopover.message(bundle: b, locale: l) == "macOS lo tiene bloqueado para Carrier. Permítelo en Ajustes del Sistema y vuelve a dictar.")
    #expect(MicrophoneBlockedPopover.button(bundle: b, locale: l) == "Abrir Ajustes del Sistema")
}

@Test func whatVoiceOverIsToldIsSaidInSpanishWithTheWordsAddedAsAPlural() {
    func said(_ notice: DictationNotice) -> String { dictationAnnouncement(notice, bundle: b, locale: l) }
    #expect(said(.gettingReady) == "Preparando el modelo" && said(.listening) == "Escuchando")
    #expect(said(.stopped(words: 0)) == "Dictado detenido, sin palabras añadidas")
    #expect(said(.stopped(words: 1)) == "Dictado detenido, 1 palabra añadida")
    #expect(said(.stopped(words: 2)) == "Dictado detenido, 2 palabras añadidas")
    #expect(said(.failed(DictationFailure(.noSpeechModel))) == "El dictado falló: No hay ningún modelo de voz disponible")
    // a system's own words are not translated
    #expect(said(.failed(DictationFailure("boom"))) == "El dictado falló: boom")
}

// MARK: why a dictation could not go on

@Test func aFailureKeepsItsEnglishCauseForTheLogAndSaysItsReasonInSpanish() {
    let cases: [(DictationFailure.Reason, String, String)] = [
        (.recognizerSilent, "The recognizer did not answer.", "El reconocedor no respondió."),
        (.modelNotReady, "The speech model did not get ready in time.", "El modelo de voz no estuvo listo a tiempo."),
        (.noSpeechModel, "No speech model is available", "No hay ningún modelo de voz disponible"),
        (.speechModelStopped("boom"), "The speech model stopped: boom", "El modelo de voz se detuvo: boom"),
        (.cleanup(.timeout), "The model did not answer in time", "El modelo no respondió a tiempo"),
        (.notAFluidAudioModel("Parakeet"), "Parakeet is not a model of FluidAudio.", "Parakeet no es un modelo de FluidAudio."),
        (.notAWhisperKitModel("Tiny"), "Tiny is not a model of WhisperKit.", "Tiny no es un modelo de WhisperKit."),
        (
            .modelCouldNotLoad(model: "Tiny", detail: "no file"),
            "Tiny could not be loaded from its folder (no file). Delete it on the Dictation page and download it again.",
            "No se pudo cargar Tiny desde su carpeta (no file). Elimínalo en la página Dictado y vuelve a descargarlo."
        ),
        (.modelNotPrepared, "The speech model was not prepared.", "El modelo de voz no se preparó."),
        (.noAudioInput, "No microphone is available: this Mac has no audio input.", "No hay ningún micrófono disponible: este Mac no tiene entrada de audio."),
        (.microphoneCouldNotStart("busy"), "The microphone could not start: busy", "El micrófono no pudo iniciarse: busy"),
        (.appleHasNoLanguage, "Apple's speech recognition does not support any language of this Mac.", "El reconocimiento de voz de Apple no admite ningún idioma de este Mac."),
        (.appleNotPrepared, "Apple's recognizer was not prepared.", "El reconocedor de Apple no se preparó."),
        (.appleHasNoAudioFormat, "Apple's speech recognition has no audio format for this Mac.", "El reconocimiento de voz de Apple no tiene un formato de audio para este Mac."),
        (.appleStopped("x"), "Apple's speech recognition stopped: x", "El reconocimiento de voz de Apple se detuvo: x"),
        (.appleCouldNotConvert, "Apple's speech recognition could not convert the audio of the microphone.", "El reconocimiento de voz de Apple no pudo convertir el audio del micrófono."),
        (.cannotDownload("Apple"), "This build cannot download Apple.", "Esta compilación no puede descargar Apple."),
        (
            .fixtureNoMicrophone, "No microphone is available: the fixture is set to fail.",
            "No hay ningún micrófono disponible: el reconocedor de prueba está configurado para fallar."
        ),
        (
            .microphoneBlocked, "macOS has the microphone blocked for Carrier. Allow it in System Settings, then dictate again.",
            "macOS tiene el micrófono bloqueado para Carrier. Permítelo en Ajustes del Sistema y vuelve a dictar."
        ),
    ]
    for (reason, cause, words) in cases {
        let failure = DictationFailure(reason)
        #expect(failure.cause == cause && failure == DictationFailure(cause), Comment(rawValue: cause))
        #expect(failure.shown(bundle: b, locale: l) == words, Comment(rawValue: cause))
        #expect(failure.shown(bundle: english.bundle, locale: english.locale) == cause)
    }
    #expect(DictationFailure("odd").shown(bundle: b, locale: l) == "odd")
}

@Test func theCleanupSaysItsFailuresInSpanishNamingTheServer() {
    func said(_ failure: CleanupFailure) -> String { failure.message(bundle: b, locale: l) }
    #expect(said(.noServer) == "Elige primero un servidor" && said(.noModel) == "El modelo no está en el servidor: elige otro")
    #expect(said(.emptyPrompt) == "El prompt está vacío" && said(.timeout) == "El modelo no respondió a tiempo")
    #expect(said(.emptyAnswer) == "El modelo respondió sin texto")
    #expect(said(.serverDown(.ollama)) == "Ollama no está en marcha" && said(.serverDown(.lmStudio)) == "LM Studio no está en marcha")
    #expect(said(.noModelList(.lmStudio)) == "LM Studio no tiene una lista de modelos")
    #expect(said(.notAModelList(.ollama)) == "Ollama respondió algo que no es una lista de modelos")
    #expect(said(.notACompletion(.ollama)) == "Ollama respondió algo que no es una respuesta del modelo")
    #expect(said(.httpStatus(.lmStudio, 500)) == "LM Studio respondió HTTP 500")
    #expect(said(.badReply("odd")) == "odd")
    #expect(cleanupSample(bundle: b, locale: l).hasPrefix("eh o sea básicamente") && cleanupSample(bundle: english.bundle, locale: english.locale).hasPrefix("um so basically"))
}

// MARK: the Dictation page

@Test func theCardOfTheDictationPageSaysWhatIsInTheWayInSpanish() {
    func card(
        enabled: Bool = true, microphone: MicrophonePermission = .allowed, trusted: Bool = true, global: Bool = true, model: DictationModelReadiness = .ready("Apple")
    ) -> DictationReadiness {
        dictationReadiness(enabled: enabled, microphone: microphone, accessibilityTrusted: trusted, globalOn: global, model: model, bundle: b, locale: l)
    }
    let ready = card()
    #expect(ready.title == "Listo para dictar" && ready.notes.isEmpty)
    #expect(ready.items.map(\.title) == ["Micrófono", "Accesibilidad", "Apple"] && ready.items.map(\.state) == ["Permitido", "Permitido", "listo"])
    let off = card(enabled: false)
    #expect(off.title == "El dictado está desactivado" && off.notes == ["No hay micrófono en el cuadro de mensaje y nada escucha."])
    let blocked = card(microphone: .denied)
    #expect(blocked.title == "Aún no puede escuchar" && blocked.items[0].state == "No permitido")
    #expect(blocked.notes.first == "macOS tiene el micrófono bloqueado para Carrier, así que el dictado no puede escuchar.")
    let asking = card(microphone: .notAsked)
    #expect(asking.items[0].state == "Aún sin pedir" && asking.notes == ["Carrier se lo pide a macOS la primera vez que dictas."])
    // one thing to fix is the singular, and two the plural
    let one = card(trusted: false)
    #expect(one.title == "Listo, con una cosa por arreglar" && one.items[1].state == "No permitido")
    #expect(one.notes == ["Sin Accesibilidad el texto va al portapapeles en vez de pegarse."])
    let two = card(trusted: false, model: .missing("Whisper Small"))
    #expect(two.title == "Listo, con 2 cosas por arreglar" && two.items[2].state == "no está en el disco")
    #expect(two.notes.first == "Whisper Small no está en el disco: descárgalo en la tabla de modelos o elige otro.")
    #expect(card(model: .downloading("Whisper Small")).items[2].state == "descargando")
}

@Test func theScreensOfThePageHaveTheirTitleAndTheirLineInSpanish() {
    let titles = DictationScreen.allCases.map { $0.title(bundle: b, locale: l) }
    #expect(titles == ["Reconocimiento de voz", "Dictado global", "Limpieza", "Sonidos", "Historial", "Estadísticas"])
    let details = DictationScreen.allCases.map { $0.detail(bundle: b, locale: l) }
    #expect(details == [
        "Modelos, idioma y memoria", "Cualquier app: su atajo y el widget", "Un modelo de este Mac reescribe lo que dijiste", "Inicio y fin de un dictado",
        "Lo que dictaste, para copiarlo de nuevo", "Cuánto dictas y el tiempo que ahorra",
    ])
}

@Test func theLanguageHintSaysWhyInSpanish() {
    func hint(_ model: SpeechModel, saved: String? = nil) -> String { languageChoices(for: model, macOSLanguages: [], saved: saved, bundle: b, locale: l).hint }
    let detecting = model("fluidaudio.parakeet", .fluidAudio, languages: ["en", "es"], detects: true)
    #expect(hint(detecting) == "Elige el idioma mientras hablas, así que puedes mezclar español e inglés")
    #expect(hint(detecting, saved: "en") == "Elige Automático para mezclar idiomas")
    #expect(hint(model("fluidaudio.nemotron", .fluidAudio)) == "Este modelo solo entiende inglés")
    #expect(hint(model("apple.speech", .apple, bytes: nil, languages: ["en", "es"])) == "apple.speech escucha en un solo idioma; elige un modelo que lo detecte para mezclarlos")
}

@Test func theChoicesOfHistoryAndMemoryAreSaidInSpanishWithTheirPlurals() {
    #expect(dictationAudioLimits.map { $0.title(bundle: b, locale: l) } == ["7 días", "30 días", "90 días", "Nunca"])
    #expect(dictationReleaseChoices.map { $0.title(bundle: b, locale: l) } == ["5 minutos", "15 minutos", "30 minutos", "60 minutos", "Nunca"])
    #expect(Copy.dictationAudioLimit(days: 1, bundle: b, locale: l) == "1 día" && Copy.dictationReleaseAfter(minutes: 1, bundle: b, locale: l) == "1 minuto")
    #expect(formatAudioOnDisk(bytes: 0, files: 0, bundle: b, locale: l) == "Sin audio")
    #expect(formatAudioOnDisk(bytes: 12_400, files: 1, bundle: b, locale: l) == "12 KB en 1 archivo")
    #expect(formatAudioOnDisk(bytes: 182_000_000, files: 214, bundle: b, locale: l) == "182 MB en 214 archivos")
}

@Test func theShortcutRecorderRefusesAndTheWidgetSaysItsKeysInSpanish() {
    #expect(recordShortcut(keyCode: 0, characters: "a", modifiers: [.shift], bundle: b, locale: l) == .refused("Añade ⌃, ⌥ o ⌘: una tecla sin modificador dejaría de escribir en todas las apps"))
    #expect(recordShortcut(keyCode: 0, characters: "ab", modifiers: [.command], bundle: b, locale: l) == .refused("Esa tecla no se puede usar"))
    #expect(dictationHint(shortcut: .standard, activation: .toggle, bundle: b, locale: l) == "⌥⇧ Space para terminar · Esc para cancelar")
    #expect(dictationHint(shortcut: .standard, activation: .hold, bundle: b, locale: l) == "Suelta ⌥⇧ Space para terminar · Esc para cancelar")
}

// MARK: the widget

@Test func theWidgetsOptionsAndNoticesAreSaidInSpanish() {
    #expect(DictationWidgetStyle.allCases.map { $0.title(bundle: b, locale: l) } == ["Píldora", "Pequeño", "Mediano", "Grande"])
    #expect(DictationWidgetTheme.allCases.map { $0.title(bundle: b, locale: l) } == ["Predeterminado", "Negro", "Cristal oscuro", "Cristal claro", "Brillo del tema"])
    #expect(DictationWidgetPosition.allCases.map { $0.title(bundle: b, locale: l) } == ["Arriba", "Abajo"])
    #expect(
        dictationKeptNotices(reason: .noField, notCleaned: nil, bundle: b, locale: l)
            == ["Ningún campo de texto tiene el cursor, así que el texto no se pegó. Está en el portapapeles."])
    #expect(
        dictationKeptNotices(reason: .secureField, notCleaned: "El modelo no respondió a tiempo", bundle: b, locale: l).last
            == "No se limpió: El modelo no respondió a tiempo")
    #expect(Copy.dictationPastedRaw(cause: "x", bundle: b, locale: l) == "Pegado sin limpiar: x")
}

// MARK: History and its audio

@Test func theHistorySaysItsDaysOutcomesAndDestinationsInSpanish() {
    let calendar = spanishCalendar
    let today = now
    let yesterday = now.addingTimeInterval(-86_400)
    #expect(dictationDayTitle(today, now: now, calendar: calendar, bundle: b, locale: l) == "Hoy")
    #expect(dictationDayTitle(yesterday, now: now, calendar: calendar, bundle: b, locale: l) == "Ayer")
    // 2023-11-10 is a Friday
    #expect(dictationDayTitle(now.addingTimeInterval(-4 * 86_400), now: now, calendar: calendar, bundle: b, locale: l) == "viernes, 10 nov")
    #expect(DictationOutcome.allCases.map { $0.title(bundle: b, locale: l) } == ["Pegado", "Copiado", "Cancelado", "Fallido"])
    let entry = { (destination: String) in
        DictationEntry(started: now, text: "hola", model: "Apple", transcription: 0.1, audio: 2, destination: destination, outcome: .copied)
    }
    #expect(entry(DictationEntry.widgetOnly).destinationShown(bundle: b, locale: l) == "Solo el widget")
    #expect(entry(DictationEntry.widgetOnly).destinationShown(bundle: english.bundle, locale: english.locale) == "Widget only")
    #expect(entry("Slack").destinationShown(bundle: b, locale: l) == "Slack")
}

@Test func theCountsOfTheDictationPageAreSaidInSpanishWithTheirPlurals() {
    #expect(Copy.dictationCount(count: 1, bundle: b, locale: l) == "1 dictado" && Copy.dictationCount(count: 3, bundle: b, locale: l) == "3 dictados")
    #expect(Copy.dictationWordsCount(count: 1, bundle: b, locale: l) == "1 palabra" && Copy.dictationWordsCount(count: 4, bundle: b, locale: l) == "4 palabras")
    #expect(Copy.dictationStreakDays(days: 1, bundle: b, locale: l) == "1 día" && Copy.dictationStreakDays(days: 5, bundle: b, locale: l) == "5 días")
    #expect(Copy.dictationShownOf(matched: 1, total: 1, bundle: b, locale: l) == "1 de 1 dictado")
    #expect(Copy.dictationShownOf(matched: 20, total: 1200, bundle: b, locale: l) == "20 de 1.200 dictados")
    #expect(Copy.dictationHourHelp(hour: "09:00", count: 1, bundle: b, locale: l) == "09:00 · 1 dictado")
    #expect(Copy.dictationHourHelp(hour: "09:00", count: 5, bundle: b, locale: l) == "09:00 · 5 dictados")
    #expect(Copy.dictationMetaWords(destination: "Slack", words: 1, audio: "2,0 s", bundle: b, locale: l) == "Slack · 1 palabra · 2,0 s")
    #expect(Copy.dictationMetaWords(destination: "Slack", words: 12, audio: "9 s", bundle: b, locale: l) == "Slack · 12 palabras · 9 s")
    #expect(Copy.dictationSummaryMonth(count: 1234, bundle: b, locale: l) == "1.234 en 30 días")
    #expect(Copy.dictationRangeDays(days: 1, bundle: b, locale: l) == "1 día")
}

// MARK: Statistics

@Test func theStatisticsAreSaidInSpanish() {
    #expect(StatisticsRange.allCases.map { $0.title(bundle: b, locale: l) } == ["7 días", "30 días", "90 días", "Todo el tiempo"])
    #expect(statisticsChange(150, from: 100, bundle: b, locale: l) == "▲ 50 % respecto al anterior")
    #expect(statisticsChange(50, from: 100, bundle: b, locale: l) == "▼ 50 % respecto al anterior")
    #expect(statisticsChange(100, from: 100, bundle: b, locale: l) == "Sin cambios respecto al anterior")
    #expect(statisticsChange(10, from: 0, bundle: b, locale: l) == nil)
    #expect(statisticsDuration(42, bundle: b, locale: l) == "42 s" && statisticsDuration(720, bundle: b, locale: l) == "12 min")
    #expect(statisticsDuration(3900, bundle: b, locale: l) == "1 h 05 min")
    let busy = dictationHours([count(daysAgo: 0, words: 5, dictations: 4, hour: 15)], range: .week, now: now, calendar: spanishCalendar)
    #expect(statisticsHoursLine(busy, bundle: b, locale: l) == "Dictas más a eso de las 15:00.")
    #expect(statisticsHoursLine(dictationHours([], range: .all, now: now, calendar: spanishCalendar), bundle: b, locale: l) == "Aún no se ha dictado nada en este rango.")
}

@Test func theWeekIsSaidInSpanishWithEachOfItsVariants() {
    func summary(_ counts: [DictationCount], wpm: Int = 40) -> String {
        weeklySummary(dictationFigures(counts, range: .week, now: now, calendar: spanishCalendar), wpm: wpm, calendar: spanishCalendar, bundle: b, locale: l)
    }
    // today is a Tuesday and Sunday, with 150 of the 200 words, is the busiest day
    let more = summary([count(daysAgo: 0, words: 50, dictations: 2, seconds: 30), count(daysAgo: 2, words: 150, dictations: 6, seconds: 90), count(daysAgo: 8, words: 100, dictations: 5, seconds: 60)])
    #expect(more == "Dictaste 200 palabras en 8 dictados, un 100 % más que en los 7 días anteriores. El domingo fue tu día con más actividad, y ahorraste unos 3 min.")
    #expect(summary([count(daysAgo: 0, words: 50), count(daysAgo: 8, words: 100)]).contains("un 50 % menos que en los 7 días anteriores"))
    #expect(summary([count(daysAgo: 0, words: 100), count(daysAgo: 8, words: 100)]).contains("lo mismo que en los 7 días anteriores"))
    // the singular of each plural
    #expect(
        summary([count(daysAgo: 0, words: 1, dictations: 1, seconds: 5)])
            == "Dictaste 1 palabra en 1 dictado, sin nada en los 7 días anteriores con lo que compararlo. El martes fue tu día con más actividad.")
    #expect(summary([count(daysAgo: 9, words: 40, dictations: 3)]) == "Ningún dictado en los últimos 7 días, frente a 3 dictados en los 7 anteriores.")
    #expect(summary([count(daysAgo: 9, words: 40, dictations: 1)]) == "Ningún dictado en los últimos 7 días, frente a 1 dictado en los 7 anteriores.")
    #expect(summary([]) == "Ningún dictado en los últimos 7 días.")
}

// MARK: speech models

@Test func theRowsOfTheSpeechModelsTableAreSaidInSpanish() {
    let apple = model("apple.speech", .apple, bytes: nil, languages: ["en", "es"])
    let parakeet = model("fluidaudio.parakeet", .fluidAudio, languages: ["de", "en", "es"], detects: true)
    let tiny = model("whisper.tiny", .whisper, bytes: 75_000_000, partial: .atTheEnd)
    let german = model("whisper.german", .whisper, bytes: 75_000_000, languages: ["de"], partial: .atTheEnd)
    let rows = speechModelRows(
        models: [apple, parakeet, tiny, german], filter: nil, state: { $0.bytes == nil || $0.id == parakeet.id ? .downloaded : .notDownloaded }, inUse: parakeet.id, bundle: b, locale: l)
    #expect(rows.map(\.size) == ["Sistema", "500 MB", "75 MB", "75 MB"])
    #expect(rows[0].licence == "Sistema" && rows[1].licence == "MIT")
    #expect(rows.map(\.languages) == ["Los idiomas de tu macOS", "3 idiomas", "Solo inglés", "Solo alemán"])
    #expect(rows.map(\.text) == ["En vivo", "En vivo", "Al parar", "Al parar"])
    #expect(rows[1].label == "fluidaudio.parakeet, FluidAudio, 500 MB, 3 idiomas, el texto aparece en vivo, en uso")
    #expect(rows[0].label == "apple.speech, Apple, Sistema, Los idiomas de tu macOS, el texto aparece en vivo, descargado")
    #expect(rows[2].label == "whisper.tiny, Whisper, 75 MB, Solo inglés, el texto aparece al parar, sin descargar")
    let downloading = speechModelRows(models: [tiny], filter: nil, state: { _ in .downloading(0.47) }, inUse: nil, bundle: b, locale: l)
    #expect(downloading[0].label.hasSuffix("descargando, 40 por ciento"))
    let failed = speechModelRows(models: [tiny], filter: nil, state: { _ in .failed("Sin conexión") }, inUse: nil, bundle: b, locale: l)
    #expect(failed[0].label.hasSuffix("falló la descarga, Sin conexión") && failed[0].action == .failed(cause: "Sin conexión"))
}

// MARK: the pasted text

@Test func aPasteIsSaidInSpanishWithItsLinesAsAPlural() {
    #expect(PasteSummary(String(repeating: "a", count: 3412), bundle: b, locale: l).stats == "3.412 caracteres · 1 línea · ~853 tokens")
    #expect(PasteSummary(Array(repeating: "x", count: 87).joined(separator: "\n"), bundle: b, locale: l).stats.contains("87 líneas"))
    #expect(messagePreview(messageWithPastes("¿por qué?", pastes: ["a\nb"]), bundle: b, locale: l) == "¿por qué?\nTexto pegado · 2 líneas")
    #expect(messagePreview(messageWithPastes("", pastes: ["a"]), bundle: b, locale: l) == "Texto pegado · 1 línea")
}

// MARK: the words the views call straight from Copy

@Test func everyDictationKeyWithNoArgumentIsInTheSpanishCatalogWithItsSpanishWords() throws {
    let file = testPaths().root.appendingPathComponent("design/copy/es.json")
    let words = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: String])
    let plain = words.filter { key, value in key.hasPrefix("dictation") && value.contains("{") == false }
    #expect(plain.count > 150)
    for (key, value) in plain {
        #expect(b.localizedString(forKey: key, value: "missing", table: nil) == value, Comment(rawValue: key))
    }
}

@Test func theWordsWithArgumentsTheDictationViewsCallAreSpanish() {
    #expect(Copy.dictationItemLine(title: "Micrófono", state: "Permitido", bundle: b, locale: l) == "Micrófono · Permitido")
    #expect(Copy.dictationSummaryGlobal(shortcut: "⌥⇧ Space", activation: "Mantener", style: "Mediano", bundle: b, locale: l) == "⌥⇧ Space · Mantener · Mediano")
    #expect(Copy.dictationSummaryCleanupOn(server: "Ollama", bundle: b, locale: l) == "Activada · Ollama")
    #expect(Copy.dictationSummarySounds(start: "Tink", end: "Pop", volume: 60, bundle: b, locale: l) == "Tink · Pop · 60 %")
    #expect(Copy.dictationAnyAppDetail(shortcut: "⌥⇧ Space", bundle: b, locale: l) == "⌥⇧ Space abre un widget en cualquier app y pega lo que dijiste en el cursor")
    #expect(Copy.dictationShortcutClearThe(name: "atajo de dictado", bundle: b, locale: l) == "Borrar atajo de dictado")
    #expect(Copy.dictationShortcutCleared(name: "Atajo de dictado", bundle: b, locale: l) == "Atajo de dictado borrado")
    #expect(Copy.dictationShortcutSet(shortcut: "⌥⇧ Space", bundle: b, locale: l) == "Atajo establecido en ⌥⇧ Space")
    #expect(Copy.dictationWidgetPreviewLabel(style: "Mediano", theme: "Negro", bundle: b, locale: l) == "Vista previa del widget Mediano, Negro")
    #expect(Copy.dictationTypingSpeedProblem(low: 10, high: 300, bundle: b, locale: l) == "Debe estar entre 10 y 300")
    #expect(Copy.dictationVolumeDetail(volume: 60, bundle: b, locale: l) == "Para los dos sonidos, solo en el dictado global; 60 %")
    #expect(Copy.dictationVolumePercent(volume: 60, bundle: b, locale: l) == "60 por ciento")
    #expect(Copy.dictationShowMore(count: 100, bundle: b, locale: l) == "Mostrar 100 más")
    #expect(Copy.dictationPerDay(metric: "Palabras", bundle: b, locale: l) == "Palabras por día")
    #expect(Copy.dictationTranscriptionValue(taken: "Al instante", audio: "6 s", bundle: b, locale: l) == "Al instante para 6 s de audio")
    #expect(Copy.dictationDeleteModelTitle(model: "Whisper Tiny", bundle: b, locale: l) == "¿Eliminar Whisper Tiny?")
    #expect(Copy.dictationDownload(size: "500 MB", bundle: b, locale: l) == "Descargar · 500 MB")
    #expect(Copy.dictationOpenCard(model: "Whisper Tiny", bundle: b, locale: l) == "Abrir la ficha de Whisper Tiny")
    #expect(Copy.dictationDownloadedModelsDetail(size: "1.2 GB", bundle: b, locale: l) == "1.2 GB en la carpeta de Carrier")
}
