import Foundation
import Testing
@testable import CarrierCore

private let start = Date(timeIntervalSince1970: 1_000_000)

private func step(
    dictation: Bool = true, keepReady: Bool = true, releaseAfter: Int = 15, loaded: Bool, idle minutes: Double = 0
) -> SpeechModelStep {
    speechModelStep(
        dictation: dictation, keepReady: keepReady, releaseAfter: releaseAfter, loaded: loaded, idleSince: start, now: start.addingTimeInterval(minutes * 60)
    )
}

@Test func withDictationAndKeepReadyOnAModelThatIsNotLoadedLoads() {
    #expect(step(loaded: false) == .load)
    #expect(step(loaded: true) == .none)
}

@Test func withKeepReadyOffNothingLoadsInTheBackgroundButALoadedModelStillReleases() {
    #expect(step(keepReady: false, loaded: false) == .none)
    #expect(step(keepReady: false, loaded: true, idle: 14) == .none)
    #expect(step(keepReady: false, loaded: true, idle: 15) == .release)
}

@Test func withDictationOffNothingLoadsAndWhatIsLoadedIsReleased() {
    #expect(step(dictation: false, loaded: false) == .none)
    #expect(step(dictation: false, loaded: true) == .release)
    #expect(step(dictation: false, keepReady: false, loaded: false) == .none)
}

@Test(arguments: [5, 15, 30, 60])
private func aModelIsReleasedOnceTheMinutesWithoutDictatingHavePassedWhateverKeepReadySays(minutes: Int) {
    for keepReady in [true, false] {
        #expect(step(keepReady: keepReady, releaseAfter: minutes, loaded: true, idle: Double(minutes) - 0.1) == .none)
        #expect(step(keepReady: keepReady, releaseAfter: minutes, loaded: true, idle: Double(minutes)) == .release)
    }
}

@Test func aReleasedModelIsNotLoadedAgainUntilSomethingAsksForItAndNeverKeepsItForGood() {
    #expect(step(loaded: false, idle: 20) == .none)
    #expect(step(releaseAfter: 0, loaded: true, idle: 100_000) == .none)
    #expect(step(releaseAfter: 0, loaded: false, idle: 100_000) == .load)
}

private actor Counter {
    var value = 0
    func next() -> Int { value += 1; return value }
}

@Test func aSlotLoadsOneModelOnceAndAsksAgainOnlyAfterARelease() async throws {
    let slot = ModelSlot<Int>(), counter = Counter()
    try await slot.load("a") { await counter.next() }
    try await slot.load("a") { await counter.next() }
    #expect(slot.current?.id == "a" && slot.current?.model == 1)
    slot.release()
    #expect(slot.current == nil)
    try await slot.load("a") { await counter.next() }
    #expect(slot.current?.model == 2)
    try await slot.load("b") { await counter.next() }
    #expect(slot.current?.id == "b" && slot.current?.model == 3)
}

@Test func twoAsksForTheModelThatIsLoadingShareTheLoad() async throws {
    let slot = ModelSlot<Int>(), counter = Counter()
    let (gate, open) = AsyncStream<Void>.makeStream()
    let make: @Sendable () async -> Int = {
        for await _ in gate {}
        return await counter.next()
    }
    async let first: Void = slot.load("a", using: make)
    async let second: Void = slot.load("a", using: make)
    try await Task.sleep(for: .milliseconds(30))
    open.finish()
    try await first
    try await second
    #expect(await counter.value == 1 && slot.current?.model == 1)
}

@Test func aReleaseWhileTheModelLoadsKeepsTheLoadedModelOut() async throws {
    let slot = ModelSlot<Int>()
    let (gate, open) = AsyncStream<Void>.makeStream()
    let loading = Task { try await slot.load("a") { for await _ in gate {}; return 1 } }
    try await Task.sleep(for: .milliseconds(30))
    slot.release()
    open.finish()
    try await loading.value
    #expect(slot.current == nil)
}

@Test func aFailedLoadIsAskedAgainTheNextTime() async throws {
    struct Broken: Error {}
    let slot = ModelSlot<Int>(), counter = Counter()
    await #expect(throws: Broken.self) { try await slot.load("a") { throw Broken() } }
    try await slot.load("a") { await counter.next() }
    #expect(slot.current?.model == 1)
}
