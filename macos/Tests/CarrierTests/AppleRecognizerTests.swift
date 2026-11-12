import AVFoundation
import CarrierCore
import Foundation
import Testing
@testable import Carrier

/// The gated tests of the feature skip themselves unless CARRIER_IT_DICTATION is set (it names the folder where downloaded models are
/// kept, which Apple's recognizer ignores): they need the system's speech assets and, for the models, files on disk.
let dictationGate = Testing.ConditionTrait.enabled(if: ProcessInfo.processInfo.environment["CARRIER_IT_DICTATION"] != nil)

/// The short Spanish clip of the test resources, made with `say`, as the buffers a capture would give.
func spanishClip() throws -> [CarrierCore.AudioBuffer] { try clip("hola-es") }

/// The English one, for the models that only understand English.
func englishClip() throws -> [CarrierCore.AudioBuffer] { try clip("hello-en") }

private func clip(_ name: String) throws -> [CarrierCore.AudioBuffer] {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "wav"))
    let file = try AVAudioFile(forReading: url)
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
    try file.read(into: buffer)
    let samples = Array(UnsafeBufferPointer(start: try #require(buffer.floatChannelData)[0], count: Int(buffer.frameLength)))
    return stride(from: 0, to: samples.count, by: 1600).map {
        CarrierCore.AudioBuffer(samples: Array(samples[$0..<min($0 + 1600, samples.count)]), sampleRate: file.processingFormat.sampleRate)
    }
}

@Test(dictationGate) func appleRecognizerGivesTextForTheSpanishClip() async throws {
    let apple = try #require(await AppleRecognizer.make(preferredLanguages: ["es-ES"]))
    let started = ContinuousClock.now
    try await apple.prepare(apple.models[0])
    print("apple prepare took \(ContinuousClock.now - started)")
    let (audio, input) = AsyncStream<CarrierCore.AudioBuffer>.makeStream()
    var heard = ""
    var partials = 0
    let events = apple.recognize(audio)
    for buffer in try spanishClip() { input.yield(buffer) }
    input.finish()
    for await event in events {
        switch event {
        case .partial: partials += 1
        case .final(let text): heard = text
        case .failed(let failure): Issue.record("failed: \(failure.cause)")
        }
    }
    print("apple heard: \(heard) (\(partials) partials)")
    #expect(heard.isEmpty == false)
}

@Test(dictationGate) func appleRecognizerEndsInAnEmptyFinalWhenNothingIsSaid() async throws {
    let apple = try #require(await AppleRecognizer.make(preferredLanguages: ["es-ES"]))
    try await apple.prepare(apple.models[0])
    let (audio, input) = AsyncStream<CarrierCore.AudioBuffer>.makeStream()
    let events = apple.recognize(audio)
    input.finish()
    var seen: [DictationEvent] = []
    for await event in events { seen.append(event) }
    #expect(seen == [.final("")])
}
