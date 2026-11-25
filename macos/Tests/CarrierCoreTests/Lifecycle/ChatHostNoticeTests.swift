import Testing
@testable import CarrierCore

@Test func nothingMissingIsNoNotice() {
    #expect(chatHostNotice(missing: [], bundle: english.bundle, locale: english.locale) == nil)
}

@Test func theNoticeNamesWhatIsMissingAndWhereToFixIt() throws {
    let one = try #require(chatHostNotice(missing: ["carrier"], bundle: english.bundle, locale: english.locale))
    #expect(one.title == "The chat host cannot start")
    #expect(one.line == "The app did not find carrier. Run brew install ashulab/tap/carrier in Terminal.")
    let both = try #require(chatHostNotice(missing: ["node", "carrier"], bundle: english.bundle, locale: english.locale))
    #expect(both.line.contains("node and carrier") && both.line.contains("brew install ashulab/tap/carrier"))
    #expect(try #require(chatHostNotice(missing: ["node"], bundle: english.bundle, locale: english.locale)).line.contains("brew") == false)
}

@Test func theNoticeIsSaidInSpanish() throws {
    let one = try #require(chatHostNotice(missing: ["carrier"], bundle: spanish.bundle, locale: spanish.locale))
    #expect(one.title == "El host de chat no puede iniciarse")
    #expect(one.line == "La app no encontró carrier. Ejecuta brew install ashulab/tap/carrier en Terminal.")
    #expect(try #require(chatHostNotice(missing: ["node", "carrier"], bundle: spanish.bundle, locale: spanish.locale)).line.hasPrefix("La app no encontró node y carrier."))
    #expect(try #require(chatHostNotice(missing: ["node"], bundle: spanish.bundle, locale: spanish.locale)).line == "La app no encontró node. Instálalo.")
}

@Test func theOlderHostNoticeIsSaidInBothLanguages() {
    #expect(chatHostRestartNotice(bundle: english.bundle, locale: english.locale).title == "The chat host is older than Carrier")
    #expect(chatHostRestartNotice(bundle: english.bundle, locale: english.locale).line.hasPrefix("A session is working, so the app left it running."))
    #expect(chatHostRestartNotice(bundle: spanish.bundle, locale: spanish.locale).title == "El host de chat es más antiguo que Carrier")
    #expect(chatHostRestartNotice(bundle: spanish.bundle, locale: spanish.locale).line.hasPrefix("Hay una sesión trabajando, así que la app lo dejó en marcha."))
}
