import Foundation

/// The level of a buffer, `0...1`, from its root mean square: decibels with a floor at -50 and a ceiling at -10. Zero, a negative and NaN
/// are silence; a clipped buffer and infinity are the ceiling.
public func normalizedLevel(rms: Float) -> Float {
    guard rms > 0 else { return 0 }
    let decibels = 20 * log10(rms)
    return min(1, max(0, (decibels + 50) / 40))
}

/// One step of the smoothing: a quarter of the way down and 60% of the way up, so the light follows a voice fast and lets go slowly.
public func smoothedLevel(from current: Float, toward target: Float) -> Float {
    current + (target - current) * (target > current ? 0.6 : 0.25)
}

/// The opacity of the box's edge while it listens.
public func dictationEdgeOpacity(level: Float) -> Double { 0.4 + 0.6 * Double(min(1, max(0, level))) }

/// Turns the capture's buffers into the level the app shows, about fifteen times a second.
public struct LevelMeter: Sendable {
    public static let rate = 15.0

    public private(set) var level: Float = 0
    private var sumOfSquares = 0.0
    private var count = 0

    public init() {}

    /// Takes a buffer; returns the new smoothed level each time about a fifteenth of a second of audio has gathered, nil in between.
    public mutating func add(_ buffer: AudioBuffer) -> Float? {
        for sample in buffer.samples {
            sumOfSquares += Double(sample * sample)
            count += 1
        }
        guard count > 0, Double(count) >= buffer.sampleRate / Self.rate else { return nil }
        level = smoothedLevel(from: level, toward: normalizedLevel(rms: Float((sumOfSquares / Double(count)).squareRoot())))
        sumOfSquares = 0
        count = 0
        return level
    }
}

/// A color by hue (`0..<1`), saturation and brightness, for the edge and the light of a dictation.
public struct HSB: Equatable, Sendable {
    public var hue: Double
    public var saturation: Double
    public var brightness: Double

    public init(hue: Double, saturation: Double, brightness: Double) {
        self.hue = hue
        self.saturation = saturation
        self.brightness = brightness
    }
}

/// The three colors of the edge, derived from the person's accent: the accent and its hue turned 40 degrees each way, with the same saturation
/// and brightness. A gray or nearly gray accent (saturation under 15%) keeps its hue and only the brightness varies.
public func dictationColors(accent: HSB) -> [HSB] {
    guard accent.saturation >= 0.15 else {
        return [accent, HSB(hue: accent.hue, saturation: accent.saturation, brightness: min(1, accent.brightness + 0.2)),
                HSB(hue: accent.hue, saturation: accent.saturation, brightness: max(0, accent.brightness - 0.2))]
    }
    func turned(_ degrees: Double) -> HSB {
        let hue = (accent.hue + degrees / 360).truncatingRemainder(dividingBy: 1)
        return HSB(hue: hue < 0 ? hue + 1 : hue, saturation: accent.saturation, brightness: accent.brightness)
    }
    return [accent, turned(40), turned(-40)]
}

/// Whether the box draws the dictation's edge, halo and light: only while it listens, and a file dragged over the box wins (its veil is the
/// one that asks for an action) so the edge waits.
public func dictationEdgeShown(_ presentation: DictationPresentation?, dropping: Bool) -> Bool {
    presentation?.inAccent == true && dropping == false
}

/// How much light the box has at `level`: about 60% at full voice and 35% of that in silence.
public func dictationLightOpacity(level: Float) -> Double { 0.6 * (0.35 + 0.65 * Double(min(1, max(0, level)))) }
