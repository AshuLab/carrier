import Foundation
import Testing
@testable import CarrierCore

@Test(arguments: [
    (Float(0), Float(0)),
    (-0.5, 0),
    (.nan, 0),
    (0.003, 0),  // about -50 dB: the floor
    (0.316, 1),  // -10 dB: the ceiling
    (0.0316, 0.5),  // -30 dB: halfway in decibels
    (4, 1),  // a clipped buffer
    (.infinity, 1),
])
func theLevelOfABufferGoesFromTheFloorToTheCeiling(rms: Float, level: Float) {
    #expect(abs(normalizedLevel(rms: rms) - level) < 0.02)
}

@Test func theLevelRisesFasterThanItFalls() {
    let up = smoothedLevel(from: 0, toward: 1)
    let down = 1 - smoothedLevel(from: 1, toward: 0)
    #expect(abs(up - 0.6) < 0.0001 && abs(down - 0.25) < 0.0001)
    #expect(up > down)
    // a voice that stops: the level lets go over several samples and never goes below zero
    var level: Float = 1
    for _ in 0..<3 { level = smoothedLevel(from: level, toward: 0) }
    #expect(level > 0.4 && level < 0.5)
}

@Test(arguments: [(Float(0), 0.4), (0.5, 0.7), (1, 1.0), (-1, 0.4), (3, 1.0)])
func theEdgeOpacityIs04Plus06TimesTheLevel(level: Float, opacity: Double) {
    #expect(abs(dictationEdgeOpacity(level: level) - opacity) < 0.0001)
}

@Test func theMeterPublishesAboutFifteenTimesASecondAndFollowsTheVoice() {
    var meter = LevelMeter()
    let rate = 16000.0
    let loud = AudioBuffer(samples: Array(repeating: 0.3, count: 1600), sampleRate: rate)  // 0.1 s
    var published = 0
    for _ in 0..<10 where meter.add(loud) != nil { published += 1 }  // one second of audio
    #expect(published == 10)
    #expect(meter.level > 0.9)
    // a buffer shorter than a fifteenth of a second waits for the next
    var short = LevelMeter()
    #expect(short.add(AudioBuffer(samples: Array(repeating: 0.3, count: 500), sampleRate: rate)) == nil)
    #expect(short.add(AudioBuffer(samples: Array(repeating: 0.3, count: 600), sampleRate: rate)) != nil)
    // silence after the voice lets the level go down gradually
    let before = meter.level
    _ = meter.add(AudioBuffer(samples: Array(repeating: 0, count: 1600), sampleRate: rate))
    #expect(meter.level < before && meter.level > before * 0.5)
}
