import Foundation
import Testing

@testable import CarrierCore

private final class FakePlayer: AudioPlayer {
    var duration: TimeInterval
    var currentTime: TimeInterval = 0
    var isPlaying = false
    var startable = true
    private(set) var calls: [String] = []

    init(duration: TimeInterval) { self.duration = duration }

    func play() -> Bool {
        calls.append("play")
        isPlaying = startable
        return startable
    }
    func pause() {
        calls.append("pause")
        isPlaying = false
    }
    func stop() {
        calls.append("stop")
        isPlaying = false
    }
}

private let url = URL(fileURLWithPath: "/audio/\(UUID().uuidString).wav")

@MainActor
@Test func anAudioFileIsOpenedWhenTheRowAppearsNotWhenItsViewIsMade() {
    var opened = 0
    let playback = AudioPlayback(url: url) { _ in
        opened += 1
        return nil
    }
    #expect(playback.failed == false)
    #expect(opened == 0)
    playback.load()
    #expect(playback.failed)
    playback.load()
    #expect(playback.failed)
    #expect(opened == 1)
}

@MainActor
@Test func theModelAsksThePlayerForTheFileItWasGivenAndShowsItsDuration() {
    var asked: URL?
    let playback = AudioPlayback(url: url) {
        asked = $0
        return FakePlayer(duration: 12)
    }
    playback.load()
    #expect(asked == url)
    #expect(playback.failed == false)
    #expect(playback.duration == 12)
}

@MainActor
@Test func toggleStartsAndPausesThePlayer() {
    let player = FakePlayer(duration: 12)
    let playback = AudioPlayback(url: url) { _ in player }
    playback.load()
    playback.toggle()
    #expect(playback.playing)
    playback.toggle()
    #expect(playback.playing == false)
    #expect(player.calls == ["play", "pause"])
}

@MainActor
@Test func aPlayerThatCannotStartLeavesItNotPlaying() {
    let player = FakePlayer(duration: 12)
    player.startable = false
    let playback = AudioPlayback(url: url) { _ in player }
    playback.load()
    playback.toggle()
    #expect(playback.playing == false)
}

@MainActor
@Test func playingAFileThatHasEndedStartsFromTheTop() {
    let player = FakePlayer(duration: 12)
    player.currentTime = 12
    let playback = AudioPlayback(url: url) { _ in player }
    playback.load()
    playback.toggle()
    #expect(player.currentTime == 0)
}

@MainActor
@Test func theModelReadsThePositionWhilePlayingAndStopsWhenThePlayerEnds() async throws {
    let player = FakePlayer(duration: 12)
    let playback = AudioPlayback(url: url) { _ in player }
    playback.load()
    playback.toggle()
    player.currentTime = 3
    try await Task.sleep(for: .milliseconds(300))
    #expect(playback.position == 3)
    player.isPlaying = false
    try await Task.sleep(for: .milliseconds(300))
    #expect(playback.playing == false)
}

@MainActor
@Test func stopStopsThePlayer() {
    let player = FakePlayer(duration: 12)
    let playback = AudioPlayback(url: url) { _ in player }
    playback.load()
    playback.toggle()
    playback.stop()
    #expect(playback.playing == false)
    #expect(player.calls == ["play", "stop"])
}
