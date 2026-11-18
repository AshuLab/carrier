import CarrierCore
import Foundation
import Testing
@testable import Carrier

/// A clock that moves only when a test says so: `sleep` waits for `advance`, which also moves `now`.
@MainActor private final class Clock {
    var now = Date(timeIntervalSince1970: 1_000_000)
    private var waiting: [UUID: CheckedContinuation<Void, Error>] = [:]
    private(set) var requested: [Duration] = []

    func sleep(_ duration: Duration) async throws {
        requested.append(duration)
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { waiting[id] = $0 }
        } onCancel: {
            Task { @MainActor in self.waiting.removeValue(forKey: id)?.resume(throwing: CancellationError()) }
        }
    }

    func advance(minutes: Double) {
        now = now.addingTimeInterval(minutes * 60)
        let all = waiting.values
        waiting = [:]
        all.forEach { $0.resume() }
    }
}

@MainActor private struct Rig {
    let clock = Clock()
    let recognizer = ScriptedRecognizer()
    let preferences: AppPreferences
    let dictation: DictationController

    init(keepReady: Bool = true, releaseAfter: Int = 15, enabled: Bool = true) {
        preferences = AppPreferences(defaults: UserDefaults(suiteName: "readiness-\(UUID().uuidString)")!)
        preferences.dictationKeepReady = keepReady
        preferences.dictationReleaseAfter = releaseAfter
        preferences.dictationEnabled = enabled
        let registry = RecognizerRegistry()
        registry.register(recognizer)
        let clock = clock
        dictation = DictationController(
            registry: registry, capture: ScriptedCapture(), preferences: preferences, sleep: { try await clock.sleep($0) }, now: { clock.now }
        )
    }

    func until(_ condition: () -> Bool) async {
        for _ in 0..<2000 where condition() == false { try? await Task.sleep(for: .milliseconds(1)) }
    }

    func settles() async { try? await Task.sleep(for: .milliseconds(30)) }
}

@MainActor @Test func openingCarrierWithDictationAndKeepReadyOnLoadsTheChosenModelInTheBackground() async {
    let rig = Rig()
    #expect(rig.recognizer.prepareCount == 0)
    rig.dictation.warmUp()
    await rig.until { rig.recognizer.prepareCount == 1 }
    #expect(rig.recognizer.prepareCount == 1 && rig.dictation.session.state == .idle)
}

@MainActor @Test func withKeepReadyOffOrDictationOffNothingLoadsAtLaunch() async {
    for rig in [Rig(keepReady: false), Rig(enabled: false)] {
        rig.dictation.warmUp()
        await rig.settles()
        #expect(rig.recognizer.prepareCount == 0)
    }
}

@MainActor @Test func turningDictationOnKeepReadyOnOrChangingTheLanguageLoadsTheModelAgainInTheBackground() async {
    let rig = Rig(keepReady: false, enabled: false)
    rig.dictation.setEnabled(true)
    await rig.settles()
    #expect(rig.recognizer.prepareCount == 0)
    rig.dictation.setKeepReady(true)
    await rig.until { rig.recognizer.prepareCount == 1 }
    rig.dictation.choose(language: "es")
    await rig.until { rig.recognizer.prepareCount == 2 }
    #expect(rig.recognizer.prepareCount == 2)
    rig.dictation.setEnabled(false)
    await rig.until { rig.recognizer.releaseCount == 1 }
    #expect(rig.recognizer.releaseCount == 1)
}

@MainActor @Test func theModelIsReleasedAfterTheMinutesWithoutDictatingAndNeverKeepsIt() async {
    let rig = Rig(releaseAfter: 15)
    rig.dictation.warmUp()
    await rig.until { rig.recognizer.prepareCount == 1 && rig.clock.requested.count == 1 }
    #expect(rig.clock.requested == [.seconds(900)])
    rig.clock.advance(minutes: 15)
    await rig.until { rig.recognizer.releaseCount == 1 }
    #expect(rig.recognizer.releaseCount == 1)

    let never = Rig(releaseAfter: 0)
    never.dictation.warmUp()
    await never.until { never.recognizer.prepareCount == 1 }
    await never.settles()
    #expect(never.clock.requested.isEmpty && never.recognizer.releaseCount == 0)
}

@MainActor @Test func theTimeWithoutDictatingCountsFromTheEndOfTheLastDictationAndAModelLoadedByItIsReleasedWithKeepReadyOff() async {
    let rig = Rig(keepReady: false, releaseAfter: 5)
    let field = DictationField(owner: "box", text: { "" }, caret: { 0 }, put: { _, _, _ in })
    rig.dictation.toggle(into: field)
    await rig.until { rig.dictation.session.state == .listening }
    // no timer of the release while it dictates (the session's own 30 s wait for the model may be there)
    #expect(rig.clock.requested.allSatisfy { $0 == .seconds(30) })
    rig.clock.advance(minutes: 4)
    rig.dictation.session.stop()
    rig.recognizer.say(.final(""))
    rig.recognizer.finish()
    // the session's own wait for the recognizer is a sleep too: the timer of the release is the one of 300 seconds
    await rig.until { rig.dictation.session.state == .idle && rig.clock.requested.last == .seconds(300) }
    #expect(rig.clock.requested.last == .seconds(300))
    rig.clock.advance(minutes: 5)
    await rig.until { rig.recognizer.releaseCount == 1 }
    #expect(rig.recognizer.releaseCount == 1)
}

@MainActor @Test func aDictationThatStartsWhileTheBackgroundWorkRunsPreparesOnlyAfterItHasEnded() async {
    let rig = Rig()
    rig.recognizer.holdPrepare()
    rig.dictation.warmUp()
    await rig.until { rig.recognizer.prepareCount == 1 }
    let field = DictationField(owner: "box", text: { "" }, caret: { 0 }, put: { _, _, _ in })
    rig.dictation.toggle(into: field)
    await rig.until { rig.dictation.session.state == .listening }
    await rig.settles()
    // the dictation waits for the background load: its own prepare has not begun, so a queued release could not undo it either
    #expect(rig.recognizer.prepareCount == 1 && rig.dictation.session.modelReady == false)
    rig.recognizer.releasePrepare()
    await rig.until { rig.dictation.session.modelReady }
    #expect(rig.recognizer.prepareCount == 2 && rig.dictation.session.failure(for: "box") == nil)
    rig.dictation.session.cancel()
}
