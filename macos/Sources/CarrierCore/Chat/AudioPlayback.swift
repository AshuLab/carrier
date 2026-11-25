import Foundation
import Observation

/// Plays the audio file of a dictation: the place it has got to, the time and whether it plays. It opens the file through `open` (the app's is
/// `SystemAudioPlayer`), and plays only while its row is on screen.
@MainActor @Observable public final class AudioPlayback {
    public private(set) var playing = false
    public private(set) var position = 0.0
    public private(set) var duration = 0.0
    private var loaded = false
    @ObservationIgnored private let url: URL
    @ObservationIgnored private let open: (URL) -> (any AudioPlayer)?
    @ObservationIgnored private var player: (any AudioPlayer)?
    @ObservationIgnored private var ticker: Task<Void, Never>?

    public init(url: URL, open: @escaping (URL) -> (any AudioPlayer)?) {
        self.url = url
        self.open = open
    }

    /// Opens the file, once: the view makes one of these at each of its inits, and only the one that appears reads the disk.
    public func load() {
        guard loaded == false else { return }
        loaded = true
        player = open(url)
        duration = player?.duration ?? 0
    }

    /// The file could not be read; false until `load` has tried.
    public var failed: Bool { loaded && player == nil }

    public func toggle() {
        guard let player else { return }
        ticker?.cancel()
        ticker = nil
        if playing {
            player.pause()
            playing = false
            return
        }
        if player.currentTime >= player.duration - 0.05 { player.currentTime = 0 }
        playing = player.play()
        ticker = Task { [weak self] in
            while Task.isCancelled == false, let self, self.playing {
                self.position = self.player?.currentTime ?? 0
                // the player stops by itself at the end
                if self.player?.isPlaying == false { self.playing = false }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    public func stop() {
        ticker?.cancel()
        player?.stop()
        playing = false
    }
}
