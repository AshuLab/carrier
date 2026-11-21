import Testing

@testable import CarrierCore

@Test func aSentenceBreaksAtItsFirstFullStopOrColonIntoTitleAndDetail() {
    #expect(splitNotice("No provider can start a session: claude is signed out, codex is not installed.") == ("No provider can start a session", "claude is signed out, codex is not installed."))
    #expect(splitNotice("The chat host is older than this app, so it cannot start a session. Restart it to use the installed Carrier.") == ("The chat host is older than this app, so it cannot start a session", "Restart it to use the installed Carrier."))
    // whichever comes first
    #expect(splitNotice("3 uncommitted files. A worktree: keeps them apart.") == ("3 uncommitted files", "A worktree: keeps them apart."))
    #expect(splitNotice("Nothing to split") == ("Nothing to split", nil))
    #expect(splitNotice("Ends with a colon: ") == ("Ends with a colon", nil))
}
