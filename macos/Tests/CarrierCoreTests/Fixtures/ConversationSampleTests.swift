import Foundation
import Testing

@testable import CarrierCore

// The two sentences of the sample conversation that Settings' Preview shows, and the work between them: the person's message and the agent's answer are copy keys,
// the tools it ran (their names, a path, a command, the output) are what a pretend host answers and stay as they are.

private func texts(_ language: (bundle: Bundle, locale: Locale)) -> (user: String, agent: String)? {
    let rows = sampleConversation(bundle: language.bundle, locale: language.locale)
    guard rows.count == 3, case .user(_, let user) = rows[0], case .agent(_, let agent, _) = rows[2] else { return nil }
    return (user, agent)
}

@Test func theSampleConversationSaysItsTwoSentencesInSpanish() {
    let found = texts(spanish)
    #expect(found?.user == "¿Puedes reintentar la subida cuando falle y decir qué cambiaste?")
    #expect(found?.agent.hasPrefix("Agregué un reintento a `upload` que lo intenta tres veces") == true)
    #expect(found?.agent.hasSuffix("como `pnpm test && pnpm typecheck`.") == true)
}

@Test func theSampleConversationKeepsItsEnglishWordsInEnglish() {
    let found = texts(english)
    #expect(found?.user == "Can you retry the upload when it fails, and say what you changed?")
    let first = "I added a retry to `upload` that tries three times with a short pause between them, and a test that fails twice before it passes. "
    let second = "The width of a message is how far a line runs before it wraps: a narrow column is easy on the eye, and a wide one fits more of a table or a long command, like `pnpm test && pnpm typecheck`."
    #expect(found?.agent == first + second)
}

@Test func theToolsOfTheSampleConversationDoNotChangeWithTheLanguage() {
    func tools(_ language: (bundle: Bundle, locale: Locale)) -> [String] {
        guard case .tools(_, let group) = sampleConversation(bundle: language.bundle, locale: language.locale)[1] else { return [] }
        return group.calls.map { "\($0.tool) \($0.arg)" }
    }
    #expect(tools(english) == ["Read src/upload/retry.ts", "Bash pnpm test"])
    #expect(tools(spanish) == tools(english))
}
