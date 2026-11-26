import Foundation
import Testing

@testable import CarrierCore

/// The index in each language, built once: `english` and `spanish` are the bundle and locale a test renders in (Languages.swift).
private let englishIndex = buildSettingsIndex(bundle: english.bundle, locale: english.locale)
private let spanishIndex = buildSettingsIndex(bundle: spanish.bundle, locale: spanish.locale)

private func index(_ language: (bundle: Bundle, locale: Locale)) -> [SettingsEntry] { language.bundle === english.bundle ? englishIndex : spanishIndex }

/// What the search finds for `query` in the language of the index.
private func found(_ query: String, _ language: (bundle: Bundle, locale: Locale) = english) -> [SettingsEntry] {
    settingsResults(query, in: index(language), bundle: language.bundle, locale: language.locale)
}

@Test func everyPlaceInTheIndexHasItsOwnAnchorAndEveryPageIsInIt() {
    let ids = englishIndex.map(\.id)
    #expect(Set(ids).count == ids.count)
    for page in SettingsPage.allCases { #expect(englishIndex.contains { $0.page == page && $0.isPage }) }
    #expect(settingsAnchor(.appearance, group: "code-and-output", row: "font") == "appearance.code-and-output.font")
    // a group is the place of its own identifier, and a page is its identifier alone
    #expect(settingsAnchor(.providers, group: "accounts", row: "accounts") == "providers.accounts")
    #expect(englishIndex.first { $0.page == .general && $0.isPage }?.id == "general")
    // the same row in two groups is two places
    #expect(settingsAnchor(.notifications, group: "carrier", row: "needs-attention") != settingsAnchor(.notifications, group: "chat", row: "needs-attention"))
}

@Test func anAnchorIsMadeOfIdentifiersSoAnotherTitleMakesTheSameAnchor() {
    let font = SettingsEntry(page: .appearance, groupID: "code-and-output", group: "Code and output", rowID: "font", title: "Font")
    let translated = SettingsEntry(page: .appearance, groupID: "code-and-output", group: "Código y salida", rowID: "font", title: "Fuente")
    #expect(font.anchor == "appearance.code-and-output.font" && translated.anchor == font.anchor && translated.id == font.id)
    // the page's own identifier is not its title, and nothing in an anchor is a title
    for page in SettingsPage.allCases { #expect(page.rawValue != page.title(bundle: english.bundle, locale: english.locale)) }
    for entry in englishIndex { #expect(entry.anchor.hasPrefix(entry.page.rawValue) && entry.anchor.contains(" ") == false, Comment(rawValue: entry.anchor)) }
    // and every row of the index has one
    #expect(englishIndex.filter { $0.isPage == false }.allSatisfy { $0.rowID.isEmpty == false })
}

@Test func aSearchFindsTheRowsThatHaveEveryWordAndListsTitlesFirst() {
    let font = found("font")
    #expect(font.contains { $0.page == .appearance && $0.title == "Font" })
    #expect(font.contains { $0.page == .terminal && $0.title == "Font" })
    // a match in the title comes before one that is only in the description
    #expect(font.first?.title == "Font")
    #expect(font.prefix(3).allSatisfy { $0.title.lowercased().contains("font") })
    // every word, in any order, across the title and the page's name
    #expect(found("terminal cursor").contains { $0.title == "Cursor style" })
    #expect(found("cursor terminal").contains { $0.title == "Blink cursor" })
    #expect(found("blink terminal font").isEmpty)
}

@Test func aSearchIgnoresCaseAndAccentsAndAnEmptyOneFindsNothing() {
    #expect(found("QUIET HOURS").contains { $0.title == "Quiet hours" })
    #expect(found("  ").isEmpty && found("").isEmpty)
    #expect(found("zzzz-no-such-setting").isEmpty)
    // a page is found by its name
    #expect(found("keybindings").first?.isPage == true)
    #expect(found("projects").first.map { $0.isPage && $0.page == .projects } == true)
}

@Test func theIndexReadsTheRowsOfTheBehaviorAndKeybindingsPagesFromTheirOwnModels() {
    let groups = behaviorGroups(bundle: english.bundle, locale: english.locale)
    for group in groups { for row in group.rows { #expect(englishIndex.contains { $0.page == .behavior && $0.groupID == group.id && $0.rowID == row.key && $0.title == row.title }) } }
    for command in ShortcutCommand.allCases {
        #expect(englishIndex.contains { $0.page == .keybindings && $0.groupID == command.group.rawValue && $0.rowID == command.rawValue && $0.title == command.title(bundle: english.bundle, locale: english.locale) })
    }
}

@Test func everyDictationScreenIsOpenedByAnEntryAndItsRowsKeepTheirAnchorUnderThePath() {
    let dictation = englishIndex.filter { $0.page == .dictation && $0.isPage == false }
    // each screen has the row that opens it, and every other row names the screen that draws it
    for screen in DictationScreen.allCases { #expect(dictation.contains { $0.title == screen.title(bundle: english.bundle, locale: english.locale) && $0.path == [screen.rawValue] }) }
    #expect(dictation.allSatisfy { $0.path.count <= 1 && ($0.path.first.map { DictationScreen(rawValue: $0) != nil } ?? true) })
    // the status card is the first screen's: no path; Typing speed is Statistics'
    #expect(dictation.first { $0.title == "Microphone" }?.path == [])
    let typing = dictation.first { $0.title == "Typing speed" }
    #expect(typing?.path == ["statistics"])
    // the anchor is what the row is called on its page; the id adds the screen, so the same row is one place and a screen another
    #expect(typing?.anchor == settingsAnchor(.dictation, group: "statistics-settings", row: "typing-speed"))
    #expect(typing?.id == "\(typing?.anchor ?? "")/statistics")
    #expect(dictation.first { $0.title == "Microphone" }.map { $0.id == $0.anchor } == true)
}

@Test func theSearchFindsTheStartFromRowOnTheSessionsPageEvenWhileItIsOff() {
    for query in ["remote", "worktree", "start", "local branch"] {
        #expect(found(query).contains { $0.page == .sessions && $0.group == "New sessions" && $0.title == "Start from" }, Comment(rawValue: query))
    }
    let rows = englishIndex.filter { $0.page == .sessions && $0.group == "New sessions" }.map(\.title)
    #expect(rows == ["Starts with", "Work in", "Start from"])
}

@Test func theSearchFindsTheSleepAfterRowByWhatAPersonWouldTypeForIt() {
    for query in ["sleep", "sleep after", "idle", "memory", "asleep", "agent", "close", "minutes", "hour", "idle sessions", "timeout", "inactive", "inactivity timeout"] {
        #expect(found(query).contains { $0.page == .sessions && $0.group == "Idle sessions" && $0.title == "Sleep after" }, Comment(rawValue: query))
    }
    // the row is on the Sessions page, in its own group between the new-session choices and the ages
    let groups = englishIndex.filter { $0.page == .sessions && $0.isPage == false }.map(\.group)
    var inOrder: [String] = []
    for group in groups where inOrder.last != group { inOrder.append(group) }
    #expect(inOrder == ["New sessions", "Idle sessions", "Archive and delete", "With these ages"])
}

// MARK: the index in both languages

/// A place of each kind, found by its title in the language of the index: the entry, its anchor and its id are the same in both.
@Test func aPageARowAGroupAndAScreenAreFoundByTheirTitleInEnglishAndInSpanish() {
    // a page entry
    #expect(found("Keybindings", english).first.map { $0.isPage && $0.page == .keybindings } == true)
    #expect(found("Atajos de teclado", spanish).first.map { $0.isPage && $0.page == .keybindings } == true)
    // a row entry
    let row = "general.menu-bar.icon-style"
    #expect(found("Icon style", english).first?.anchor == row && found("Icon style", english).first?.title == "Icon style")
    #expect(found("Estilo del icono", spanish).first?.anchor == row && found("Estilo del icono", spanish).first?.title == "Estilo del icono")
    // a group entry: the group of Local servers is its own row
    let group = "providers.local-servers"
    #expect(found("Local servers", english).first { $0.groupID == "local-servers" }?.anchor == group)
    #expect(found("Servidores locales", spanish).first { $0.groupID == "local-servers" }.map { $0.anchor == group && $0.group == "Servidores locales" } == true)
    // a screen entry of the Dictation page: its path says the screen, and the anchor does not change
    let typing = "dictation.statistics-settings.typing-speed"
    #expect(found("Typing speed", english).first.map { $0.anchor == typing && $0.path == ["statistics"] } == true)
    #expect(found("Velocidad de escritura", spanish).first.map { $0.anchor == typing && $0.path == ["statistics"] } == true)
    let screen = found("Reconocimiento de voz", spanish).first { $0.rowID == "recognition" }
    #expect(screen?.path == ["recognition"] && screen?.group == "Configurar")
}

@Test func theWordsOfAnEntryAreInTheLanguageOfTheIndexAndItsDetailIsFoundToo() {
    let quiet = englishIndex.first { $0.rowID == "quiet-hours" }, tranquilo = spanishIndex.first { $0.rowID == "quiet-hours" }
    #expect(quiet?.title == "Quiet hours" && quiet?.detail == "Notifications wait in the Notification Center")
    #expect(tranquilo?.title == "Horas de silencio" && tranquilo?.detail == "Las notificaciones esperan en el Centro de notificaciones")
    // the page's name is read in the language of the index too: a word of the page finds its rows
    #expect(found("terminal cursor", english).contains { $0.title == "Cursor style" })
    #expect(found("apariencia fuente", spanish).contains { $0.page == .appearance && $0.title == "Fuente" })
    // the detail of a row is searched
    #expect(found("Centro de notificaciones", spanish).contains { $0.rowID == "quiet-hours" })
    // the keywords of a row are searched and never shown: what a person may type for Sleep after, in each language
    #expect(found("inactivity timeout", english).contains { $0.rowID == "sleep-after" })
    #expect(found("tiempo de inactividad", spanish).contains { $0.rowID == "sleep-after" })
    #expect(englishIndex.first { $0.rowID == "sleep-after" }?.detail.contains("timeout") == false)
    // the shortcut of a row of Keybindings and the stage of a role of Roles are sentences with arguments
    #expect(spanishIndex.first { $0.rowID == "newSession" }?.detail == "Predeterminado: ⌘N")
    #expect(englishIndex.first { $0.rowID == "newSession" }?.detail == "Default: ⌘N")
    #expect(spanishIndex.first { $0.page == .roles && $0.groupID == "skills" }?.detail.contains(". Ejecuta la skill ") == true)
    #expect(englishIndex.first { $0.page == .roles && $0.groupID == "skills" }?.detail.contains(". Runs the skill ") == true)
}

@Test func theAnchorAndTheIdOfEveryEntryAreTheSameInEnglishAndInSpanishAndEachIsUnique() {
    #expect(englishIndex.map(\.anchor) == spanishIndex.map(\.anchor))
    #expect(englishIndex.map(\.id) == spanishIndex.map(\.id))
    #expect(englishIndex.map(\.path) == spanishIndex.map(\.path) && englishIndex.map(\.groupID) == spanishIndex.map(\.groupID) && englishIndex.map(\.rowID) == spanishIndex.map(\.rowID))
    for language in [englishIndex, spanishIndex] { #expect(Set(language.map(\.id)).count == language.count) }
    // Spanish is not English with the keys missing: a key that is missing reads as the key itself, which no entry may
    for entry in spanishIndex { for key in entry.copyKeys { #expect(entry.title != key && entry.detail != key && entry.group != key, Comment(rawValue: key)) } }
}

@Test func theSearchFindsEachExtraReviewersRowAndOpensItsScreen() {
    for position in RoleSlot.extraPositions {
        let entry = englishIndex.first { $0.page == .roles && $0.rowID == "reviewer-\(position)" }
        #expect(entry?.title == "Reviewer \(position)" && entry?.groupID == "how-an-epic-runs" && entry?.path.isEmpty == true)
    }
}
