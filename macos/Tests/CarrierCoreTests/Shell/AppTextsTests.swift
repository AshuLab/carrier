import Testing
@testable import CarrierCore

// The words of the alerts the shell raises and of its windows' titles, in both languages.

@Test func theStopAlertCountsTheEpicsAndAgreesWithThem() {
    let one = stopCarrierAlert(interrupting: 1, bundle: english.bundle, locale: english.locale)
    #expect(one.title == "Stop Carrier?")
    #expect(one.message == "1 epic will be interrupted. It resumes on the next start, but what it was doing right now is lost.")
    #expect(one.buttons == ["Stop Carrier", "Cancel"])
    let many = stopCarrierAlert(interrupting: 3, bundle: english.bundle, locale: english.locale)
    #expect(many.message == "3 epics will be interrupted. They resume on the next start, but what they were doing right now is lost.")

    let uno = stopCarrierAlert(interrupting: 1, bundle: spanish.bundle, locale: spanish.locale)
    #expect(uno.title == "¿Detener Carrier?")
    #expect(uno.message == "Se interrumpirá 1 epic. Se reanuda en el próximo inicio, pero lo que estaba haciendo ahora mismo se pierde.")
    #expect(uno.buttons == ["Detener Carrier", "Cancelar"])
    let varios = stopCarrierAlert(interrupting: 3, bundle: spanish.bundle, locale: spanish.locale)
    #expect(varios.message == "Se interrumpirán 3 epics. Se reanudan en el próximo inicio, pero lo que estaban haciendo ahora mismo se pierde.")
}

@Test func theRenameAlertAsksForTheTitle() {
    let en = renameSessionAlert(bundle: english.bundle, locale: english.locale)
    #expect(en == AlertText(title: "Rename session", message: nil, buttons: ["Rename", "Cancel"]))
    let es = renameSessionAlert(bundle: spanish.bundle, locale: spanish.locale)
    #expect(es == AlertText(title: "Renombrar sesión", message: nil, buttons: ["Renombrar", "Cancelar"]))
}

@Test func theQuestionAlertKeepsTheQuestionsWordsAndTranslatesCancel() {
    let question = Question(title: "Delete it?", message: "It cannot be undone.", confirm: "Delete")
    #expect(questionAlert(question, bundle: english.bundle, locale: english.locale) == AlertText(title: "Delete it?", message: "It cannot be undone.", buttons: ["Cancel", "Delete"]))
    #expect(questionAlert(question, bundle: spanish.bundle, locale: spanish.locale).buttons == ["Cancelar", "Delete"])
}

@Test func theMissingTerminalAlertSaysItIsNotInstalled() {
    #expect(terminalMissingAlert(bundle: english.bundle, locale: english.locale).title == "Terminal is not installed.")
    #expect(terminalMissingAlert(bundle: spanish.bundle, locale: spanish.locale).title == "Terminal no está instalado.")
}

@Test func theWindowTitlesReadInBothLanguages() {
    #expect(mainWindowTitle(bundle: english.bundle, locale: english.locale) == "Carrier")
    #expect(mainWindowTitle(bundle: spanish.bundle, locale: spanish.locale) == "Carrier")
    #expect(Copy.settingsWindowTitle(bundle: english.bundle, locale: english.locale) == "Settings")
    #expect(Copy.settingsWindowTitle(bundle: spanish.bundle, locale: spanish.locale) == "Ajustes")
}
