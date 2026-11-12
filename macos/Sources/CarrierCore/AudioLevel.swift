import Foundation

/// The level of a buffer, `0...1`, from its root mean square: decibels with a floor at -52, under a quiet room's hiss, and a ceiling at -22, which a
/// voice at the microphone reaches. Zero, a negative and NaN are silence; a clipped buffer and infinity are the ceiling.
public func normalizedLevel(rms: Float) -> Float {
    guard rms > 0 else { return 0 }
    let decibels = 20 * log10(rms)
    return min(1, max(0, (decibels + 52) / 30))
}

/// How loud the voice is, `0...1` each, as a whole and in three bands: low (under about 250 Hz, the body of a voice), mid (up to about 2.5 kHz,
/// the vowels) and high (above it, the consonants and the breath).
public struct VoiceLevels: Equatable, Sendable {
    public var overall: Float
    public var low: Float
    public var mid: Float
    public var high: Float

    public static let silence = VoiceLevels(overall: 0, low: 0, mid: 0, high: 0)

    public init(overall: Float, low: Float, mid: Float, high: Float) {
        self.overall = overall
        self.low = low
        self.mid = mid
        self.high = high
    }
}

/// Turns the capture's buffers into the levels the app shows, about thirty times a second and as they were heard: the smoothing is the view's,
/// frame by frame (`VoiceFollower`), so a peak is not blunted before it is drawn.
public struct LevelMeter: Sendable {
    public static let rate = 30.0
    /// Where the bands split, in hertz.
    static let lowEdge = 250.0
    static let highEdge = 2500.0
    // ponytail: speech carries less energy up high, so each band is lifted by an empirical gain; tune by eye if the highs stay dull or flicker
    static let gains: (low: Float, mid: Float, high: Float) = (1, 1.6, 3.5)

    public private(set) var levels = VoiceLevels.silence
    public var level: Float { levels.overall }
    // one-pole filters: `lowPass` is what is under the low edge, `midPass` what is under the high edge
    private var lowPass = 0.0
    private var midPass = 0.0
    private var sums = (overall: 0.0, low: 0.0, mid: 0.0, high: 0.0)
    private var count = 0

    public init() {}

    /// Takes a buffer; returns the levels each time about a thirtieth of a second of audio has gathered, nil in between.
    public mutating func add(_ buffer: AudioBuffer) -> VoiceLevels? {
        let lowAlpha = 1 - exp(-2 * Double.pi * Self.lowEdge / buffer.sampleRate)
        let highAlpha = 1 - exp(-2 * Double.pi * Self.highEdge / buffer.sampleRate)
        for sample in buffer.samples {
            let x = Double(sample)
            lowPass += lowAlpha * (x - lowPass)
            midPass += highAlpha * (x - midPass)
            let (low, mid, high) = (lowPass, midPass - lowPass, x - midPass)
            sums.overall += x * x
            sums.low += low * low
            sums.mid += mid * mid
            sums.high += high * high
        }
        count += buffer.samples.count
        guard count > 0, Double(count) >= buffer.sampleRate / Self.rate else { return nil }
        func band(_ sum: Double, _ gain: Float) -> Float { normalizedLevel(rms: Float((sum / Double(count)).squareRoot()) * gain) }
        levels = VoiceLevels(
            overall: band(sums.overall, 1), low: band(sums.low, Self.gains.low), mid: band(sums.mid, Self.gains.mid), high: band(sums.high, Self.gains.high)
        )
        sums = (0, 0, 0, 0)
        count = 0
        return levels
    }
}

/// What the view shows of the levels: it goes up to a new one in about 30 ms and lets go of it in about 200 ms, stepped on every frame so the
/// motion flows between the thirty readings a second.
public struct VoiceFollower: Sendable {
    public static let attack = 0.03
    public static let release = 0.2

    public private(set) var shown = VoiceLevels.silence

    public init() {}

    public mutating func step(toward target: VoiceLevels, seconds: Double) {
        func follow(_ current: Float, _ target: Float) -> Float {
            let tau = target > current ? Self.attack : Self.release
            return current + (target - current) * Float(1 - exp(-max(0, seconds) / tau))
        }
        shown = VoiceLevels(
            overall: follow(shown.overall, target.overall), low: follow(shown.low, target.low),
            mid: follow(shown.mid, target.mid), high: follow(shown.high, target.high)
        )
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
