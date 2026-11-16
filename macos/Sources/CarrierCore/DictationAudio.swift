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
public let dictationAudioLimits: [(days: Int, title: String)] = [(7, "7 days"), (30, "30 days"), (90, "90 days"), (0, "Never")]

/// "182 MB in 214 files", "12 KB in 1 file" or "No audio" (decimal, as `formatModelSize`).
public func formatAudioOnDisk(bytes: Int, files: Int) -> String {
    guard files > 0 else { return "No audio" }
    let size = bytes >= 1_000_000 ? formatModelSize(Int64(bytes)) : "\(max(1, bytes / 1000)) KB"
    return "\(size) in \(files) \(files == 1 ? "file" : "files")"
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
