import AppKit
import CarrierCore

/// Plays a sound of macOS at the volume of the Sounds group. One at a time: a new one cuts the one before. It has no automated test.
@MainActor enum DictationSoundPlayer {
    private static var playing: NSSound?

    static func play(_ sound: SoundToPlay) {
        playing?.stop()
        playing = NSSound(named: NSSound.Name(sound.name))
        playing?.volume = Float(sound.volume)
        playing?.play()
    }
}
