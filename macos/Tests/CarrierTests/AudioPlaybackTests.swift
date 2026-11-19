import Foundation
import Testing
@testable import Carrier

@MainActor
@Test func anAudioFileIsOpenedWhenTheRowAppearsNotWhenItsViewIsMade() {
    let playback = AudioPlayback(url: URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).wav"))
    #expect(playback.failed == false)
    playback.load()
    #expect(playback.failed)
    playback.load()
    #expect(playback.failed)
}
