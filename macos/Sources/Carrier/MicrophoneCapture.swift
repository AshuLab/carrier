import AVFoundation
import AppKit
import CarrierCore

/// What macOS lets Carrier do with the microphone: its state, and the question the first click asks.
struct MicrophoneAccess {
    var status: () -> MicrophonePermission
    var request: () async -> Bool

    static let system = MicrophoneAccess(
        status: {
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: .allowed
            case .notDetermined: .notAsked
            default: .denied
            }
        },
        request: { await AVCaptureDevice.requestAccess(for: .audio) }
    )

    static let allowed = MicrophoneAccess(status: { .allowed }, request: { true })

    static func openSystemSettings() {
        if let url = URL(string: MicrophoneBlockedPopover.settingsURL) { NSWorkspace.shared.open(url) }
    }
}

/// The audio capture over the system's microphone: gives its mono buffers to the recognizer and the levels, about thirty times a second,
/// to `onLevel`. The audio lives in memory only: `stop` takes the tap off and ends the stream, and nothing is written anywhere. When the system
/// changes the input while it listens (AirPods plugged, a USB microphone pulled) the engine stops and the tap goes quiet for good, so the capture
/// stops itself: the stream ends, the dictation keeps what was heard and the person starts it again on the new microphone.
final class MicrophoneCapture: AudioCapture, @unchecked Sendable {
    private let lock = NSLock()
    private var engine: AVAudioEngine?
    private var continuation: AsyncStream<CarrierCore.AudioBuffer>.Continuation?
    private var deviceWatch: NSObjectProtocol?
    var onLevel: (@Sendable (VoiceLevels) -> Void)?

    func start() throws -> AsyncStream<CarrierCore.AudioBuffer> {
        stop()
        let engine = AVAudioEngine()
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw DictationFailure("No microphone is available: this Mac has no audio input.") }
        let (stream, continuation) = AsyncStream<CarrierCore.AudioBuffer>.makeStream()
        var meter = LevelMeter()
        let onLevel = onLevel
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            guard let channel = buffer.floatChannelData?[0] else { return }
            let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            let heard = CarrierCore.AudioBuffer(samples: samples, sampleRate: format.sampleRate)
            continuation.yield(heard)
            if let level = meter.add(heard) { onLevel?(level) }
        }
        do { try engine.start() } catch {
            engine.inputNode.removeTap(onBus: 0)
            continuation.finish()
            throw DictationFailure("The microphone could not start: \(error.localizedDescription)")
        }
        // the engine's configuration changes when the input device does; queue nil runs it on the posting thread, as `stop` is safe from any
        let watch = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in self?.stop() }
        lock.withLock {
            self.engine = engine
            self.continuation = continuation
            deviceWatch = watch
        }
        return stream
    }

    func stop() {
        let (engine, continuation, watch) = lock.withLock { () -> (AVAudioEngine?, AsyncStream<CarrierCore.AudioBuffer>.Continuation?, NSObjectProtocol?) in
            defer { (self.engine, self.continuation, deviceWatch) = (nil, nil, nil) }
            return (self.engine, self.continuation, deviceWatch)
        }
        guard let engine else { return }
        if let watch { NotificationCenter.default.removeObserver(watch) }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation?.finish()
        onLevel?(.silence)
    }
}
