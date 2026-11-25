import CarrierCore
import SwiftUI

/// A dictation's audio: a button that plays and pauses, the place it has got to and the time (`AudioPlayback` decides). It plays only while it is on screen.
struct AudioPlayerView: View {
    let url: URL
    @State private var playback: AudioPlayback

    init(url: URL) {
        self.url = url
        _playback = State(initialValue: AudioPlayback(url: url, open: SystemAudioPlayer.init(url:)))
    }

    var body: some View {
        HStack(spacing: Tokens.Space.sm) {
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
