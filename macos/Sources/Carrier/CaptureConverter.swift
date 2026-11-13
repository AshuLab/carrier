import AVFoundation
import CarrierCore
import Foundation

/// Puts the capture's mono Float samples in the format a recognizer asks for.
final class CaptureConverter {
    private let source: AVAudioFormat
    private let target: AVAudioFormat
    private let converter: AVAudioConverter

    init?(from sampleRate: Double, to target: AVAudioFormat) {
        guard let source = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: source, to: target) else { return nil }
        (self.source, self.target, self.converter) = (source, target, converter)
    }

    func convert(_ heard: CarrierCore.AudioBuffer) -> AVAudioPCMBuffer? {
        guard heard.samples.isEmpty == false, let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(heard.samples.count)),
              let channel = input.floatChannelData?[0] else { return nil }
        heard.samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: heard.samples.count) }
        input.frameLength = AVAudioFrameCount(heard.samples.count)
        let capacity = AVAudioFrameCount(Double(heard.samples.count) * target.sampleRate / source.sampleRate) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var consumed = false
        var failure: NSError?
        converter.convert(to: output, error: &failure) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return input
        }
        return failure == nil && output.frameLength > 0 ? output : nil
    }
}
