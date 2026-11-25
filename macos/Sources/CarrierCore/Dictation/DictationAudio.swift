import Foundation

// The audio of a dictation, for the history that keeps it (docs/adr/0031-dictation-keeps-a-history-and-its-statistics-live-apart-from-it.md): what the
// session gathers while it listens and the WAV file the history writes from it, which any player reads.

/// What a dictation heard: mono samples at the microphone's rate.
public struct AudioClip: Sendable, Equatable {
    public let samples: [Float]
    public let sampleRate: Double

    public init(samples: [Float], sampleRate: Double) {
        self.samples = samples
        self.sampleRate = sampleRate
    }
}

/// The days after which the audio is deleted that the History settings offer, 0 being never.
public let dictationAudioLimits = [DictationAudioLimit(days: 7), DictationAudioLimit(days: 30), DictationAudioLimit(days: 90), DictationAudioLimit(days: 0)]

public struct DictationAudioLimit: Equatable, Sendable {
    public let days: Int

    /// "7 days", or "Never" for 0.
    public func title(bundle: Bundle? = nil, locale: Locale = .current) -> String { Copy.dictationAudioLimit(days: days, bundle: bundle, locale: locale) }
}

/// "182 MB in 214 files", "12 KB in 1 file" or "No audio" (decimal, as `formatModelSize`).
public func formatAudioOnDisk(bytes: Int, files: Int, bundle: Bundle? = nil, locale: Locale = .current) -> String {
    guard files > 0 else { return Copy.dictationAudioNone(bundle: bundle, locale: locale) }
    let size = bytes >= 1_000_000 ? formatModelSize(Int64(bytes)) : Copy.dictationSizeKB(count: max(1, bytes / 1000), bundle: bundle, locale: locale)
    return Copy.dictationAudioOnDisk(size: size, files: files, bundle: bundle, locale: locale)
}

/// The clip as a WAV file: 16-bit PCM, mono.
public func wavData(_ clip: AudioClip) -> Data {
    let rate = UInt32(clip.sampleRate.rounded())
    let bytes = UInt32(clip.samples.count * 2)
    var data = Data()
    func put<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
    data.append(contentsOf: Array("RIFF".utf8))
    put(36 + bytes)
    data.append(contentsOf: Array("WAVEfmt ".utf8))
    put(UInt32(16))
    put(UInt16(1))  // PCM
    put(UInt16(1))  // mono
    put(rate)
    put(rate * 2)  // bytes a second
    put(UInt16(2))  // bytes a frame
    put(UInt16(16))
    data.append(contentsOf: Array("data".utf8))
    put(bytes)
    for sample in clip.samples { put(sample.isFinite ? Int16(max(-1, min(1, sample)) * Float(Int16.max)) : 0) }
    return data
}
