import AVFoundation
import CarrierCore
import Observation
import SwiftUI

/// Plays the audio file of a dictation: a button that plays and pauses, the place it has got to and the time. It plays only while it is on screen.
@MainActor @Observable final class AudioPlayback {
    private(set) var playing = false
    private(set) var position = 0.0
    private(set) var duration = 0.0
    private var loaded = false
    @ObservationIgnored private let url: URL
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var ticker: Task<Void, Never>?

    init(url: URL) { self.url = url }

    /// Opens the file, once: the view makes one of these at each of its inits, and only the one that appears reads the disk.
    func load() {
        guard loaded == false else { return }
        loaded = true
        player = try? AVAudioPlayer(contentsOf: url)
        duration = player?.duration ?? 0
    }

    /// The file could not be read; false until `load` has tried.
    var failed: Bool { loaded && player == nil }

    func toggle() {
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

    func stop() {
        ticker?.cancel()
        player?.stop()
        playing = false
    }
}

struct AudioPlayerView: View {
    let url: URL
    @State private var playback: AudioPlayback

    init(url: URL) {
        self.url = url
        _playback = State(initialValue: AudioPlayback(url: url))
    }

    var body: some View {
        HStack(spacing: 8) {
            IconButton(icon: playback.playing ? .pauseFilled : .playFilled, name: playback.playing ? "Pause audio" : "Play audio", enabled: playback.failed == false, why: "The audio could not be read") {
                playback.toggle()
            }
            if playback.failed {
                Text("The audio could not be read").font(.scaled(11)).foregroundStyle(.secondary)
            } else {
                ProgressView(value: playback.position, total: max(playback.duration, 0.1)).frame(maxWidth: 220)
                Text("\(dictationClock(playback.position)) / \(dictationClock(playback.duration))").font(.scaled(11)).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .onAppear { playback.load() }
        .onDisappear { playback.stop() }
    }
}
