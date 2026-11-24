import AVFoundation
import CarrierCore

/// `AudioPlayer` on `AVAudioPlayer`; nil when the file cannot be read.
final class SystemAudioPlayer: AudioPlayer {
    private let player: AVAudioPlayer

    init?(url: URL) {
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        self.player = player
    }

    var duration: TimeInterval { player.duration }
    var currentTime: TimeInterval {
        get { player.currentTime }
        set { player.currentTime = newValue }
    }
    var isPlaying: Bool { player.isPlaying }
    func play() -> Bool { player.play() }
    func pause() { player.pause() }
    func stop() { player.stop() }
}
