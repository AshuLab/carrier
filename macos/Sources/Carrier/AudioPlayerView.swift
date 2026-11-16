import AVFoundation
import CarrierCore
import Observation
import SwiftUI

/// Plays the audio file of a dictation: a button that plays and pauses, the place it has got to and the time. It plays only while it is on screen.
@MainActor @Observable private final class AudioPlayback {
    private(set) var playing = false
    private(set) var position = 0.0
    private(set) var duration = 0.0
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var ticker: Task<Void, Never>?

    init(url: URL) {
        player = try? AVAudioPlayer(contentsOf: url)
        duration = player?.duration ?? 0
    }

    var failed: Bool { player == nil }

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
            IconButton(icon: playback.playing ? "pause.fill" : "play.fill", name: playback.playing ? "Pause audio" : "Play audio", enabled: playback.failed == false, why: "The audio could not be read") {
                playback.toggle()
            }
            if playback.failed {
                Text("The audio could not be read").font(.scaled(11)).foregroundStyle(.secondary)
            } else {
                ProgressView(value: playback.position, total: max(playback.duration, 0.1)).frame(maxWidth: 220)
                Text("\(dictationClock(playback.position)) / \(dictationClock(playback.duration))").font(.scaled(11)).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .onDisappear { playback.stop() }
    }
}
