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
