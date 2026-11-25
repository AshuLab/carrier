import Testing
@testable import CarrierCore

@Test func aPublishedChangeIsReadWithItsPullRequestAndBranch() {
    #expect(publishedNote("created 946 (feat/the-chat-host/910-host-wiring)", bundle: english.bundle, locale: english.locale) == PublishedNote(verb: "Created", number: 946, identifier: "946", branch: "feat/the-chat-host/910-host-wiring"))
    #expect(publishedNote("pushed 738", bundle: english.bundle, locale: english.locale) == PublishedNote(verb: "Pushed to", number: 738, identifier: "738", branch: nil))
    #expect(publishedNote("created #12 (main)", bundle: english.bundle, locale: english.locale)?.number == 12)
}

@Test func anIdentifierThatIsNotANumberStaysAnIdentifier() {
    let note = publishedNote("updated abc123 (main)", bundle: english.bundle, locale: english.locale)
    #expect(note?.number == nil)
    #expect(note?.identifier == "abc123")
}

@Test func anyOtherNoteIsNotAPublishedChange() {
    #expect(publishedNote("Output was cut: 4 KB of 90 KB shown.", bundle: english.bundle, locale: english.locale) == nil)
    #expect(publishedNote("created", bundle: english.bundle, locale: english.locale) == nil)
    #expect(publishedNote("deleted 5 (main)", bundle: english.bundle, locale: english.locale) == nil)
    #expect(publishedNote("created 5 main", bundle: english.bundle, locale: english.locale) == nil)
}
