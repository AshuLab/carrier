import Foundation
import Testing
@testable import CarrierCore

private func heard(_ recognizer: FixtureRecognizer, stopAfterFinal: Bool) async throws -> [DictationEvent] {
    let capture = ScriptedCapture()
    let audio = try capture.start()
    if stopAfterFinal == false { capture.stop() }
    var events: [DictationEvent] = []
    for await event in recognizer.recognize(audio) {
        events.append(event)
        if stopAfterFinal, case .final = event { capture.stop() }
    }
    return events
}

@Test func theFixtureSpeaksItsPhraseWordByWordAndThenGivesTheFinal() async throws {
    let events = try await heard(FixtureRecognizer(sleep: { _ in }), stopAfterFinal: true)
    let words = FixtureRecognizer.phrase.split(separator: " ")
    #expect(events.count == words.count + 1)
    #expect(events.first == .partial(String(words[0])))
    #expect(events[1] == .partial("\(words[0]) \(words[1])"))
    #expect(events.last == .final(FixtureRecognizer.phrase))
}

@Test func theFixtureThatGivesItsTextAtTheEndSaysNothingUntilTheAudioEnds() async throws {
    let recognizer = FixtureRecognizer(mode: .atTheEnd, sleep: { _ in })
    #expect(recognizer.models.first?.partial == .atTheEnd)
    #expect(try await heard(recognizer, stopAfterFinal: false) == [.final(FixtureRecognizer.phrase)])
}

@Test func theFixtureThatFailsToStartFailsWithACause() async {
    await #expect(throws: DictationFailure("No microphone is available: the fixture is set to fail.")) {
        let recognizer = FixtureRecognizer(mode: .failsToStart, sleep: { _ in })
        try await recognizer.prepare(recognizer.models[0])
    }
}
