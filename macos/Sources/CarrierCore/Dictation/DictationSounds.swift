import Foundation

// The sounds of the global dictation (docs/specs/global-dictation.md, story 14): which one plays at each moment of a dictation, apart from the playing.

/// The system sounds on offer, by their name in `/System/Library/Sounds`.
public let dictationSoundChoices = ["Tink", "Pop", "Glass"]

/// What the Sounds group sets: a start and an end sound, each on or off and one of `dictationSoundChoices`, and one volume from 0 to 100.
public struct DictationSounds: Equatable, Sendable {
    public static let defaultStart = "Tink"
    public static let defaultEnd = "Pop"
    public static let defaultVolume = 60
    public static let volumeRange = 0...100

    public var startOn = true
    public var start = defaultStart
    public var endOn = true
    public var end = defaultEnd
    public var volume = defaultVolume

    public init() {}
}

/// A sound to play: its name and its volume from 0 to 1.
public struct SoundToPlay: Equatable, Sendable {
    public let name: String
    public let volume: Double

    public init(name: String, volume: Double) {
        self.name = name
        self.volume = volume
    }
}

/// The sound a moment of the global dictation plays, nil for none: the start sound when it begins to listen, the end sound when it stops listening
/// and goes on, none for a cancel (nothing goes on), none for a sound that is off, none at volume 0.
public func dictationSound(for moment: GlobalDictationMoment, _ sounds: DictationSounds) -> SoundToPlay? {
    guard sounds.volume > 0 else { return nil }
    let volume = Double(min(sounds.volume, DictationSounds.volumeRange.upperBound)) / 100
    switch moment {
    case .listening: return sounds.startOn ? SoundToPlay(name: sounds.start, volume: volume) : nil
    case .stopped: return sounds.endOn ? SoundToPlay(name: sounds.end, volume: volume) : nil
    case .cancelled: return nil
    }
}
