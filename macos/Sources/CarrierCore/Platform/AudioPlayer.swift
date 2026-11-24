import Foundation

/// One audio file opened for playing; the app's is `AVAudioPlayer` (`Carrier/Platform/SystemAudioPlayer.swift`), the tests of `AudioPlayback` take a fake.
public protocol AudioPlayer: AnyObject {
    /// Seconds in the file.
    var duration: TimeInterval { get }
    /// Seconds played so far; set to move to a place.
    var currentTime: TimeInterval { get set }
    /// False once the file has played to its end.
    var isPlaying: Bool { get }
    /// False when it could not start.
    func play() -> Bool
    func pause()
    func stop()
}
