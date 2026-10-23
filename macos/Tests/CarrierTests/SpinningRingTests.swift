import AppKit
import SwiftUI
import Testing
@testable import Carrier
import CarrierCore

@Test func aRingToldToAnimateTurnsCappedAt20Fps() throws {
    let ring = RingLayer.make(diameter: 16, lineWidth: 2.5, color: NSColor.systemGreen.cgColor, animate: true)
    let spin = try #require(ring.arc.animation(forKey: RingLayer.spinKey) as? CABasicAnimation)
    #expect(spin.preferredFrameRateRange == CAFrameRateRange(minimum: 20, maximum: 20, preferred: 20))
    #expect(spin.repeatCount == .infinity)
    #expect(spin.keyPath == "transform.rotation.z")
    #expect(ring.track.animationKeys() == nil)
}

@Test func aRingNotToldToAnimateHasNoAnimation() {
    let ring = RingLayer.make(diameter: 16, lineWidth: 2.5, color: NSColor.systemGreen.cgColor, animate: false)
    #expect(ring.animationKeys() == nil && ring.arc.animationKeys() == nil && ring.track.animationKeys() == nil)
}

@Test func animatingTwiceKeepsTheSameAnimationAndStoppingRemovesIt() throws {
    let ring = RingLayer.make(diameter: 16, lineWidth: 2.5, color: NSColor.systemGreen.cgColor, animate: true)
    let first = try #require(ring.arc.animation(forKey: RingLayer.spinKey))
    ring.setAnimating(true)
    #expect(ring.arc.animation(forKey: RingLayer.spinKey) === first)
    ring.setAnimating(false)
    #expect(ring.arc.animationKeys() == nil)
}

@MainActor @Test func theHostTurnsTheRingOnlyWhenTheWindowIsVisibleAndMotionIsAllowed() {
    let host = RingHostView(diameter: 16, lineWidth: 2.5, color: .systemGreen)
    #expect(host.animating == false)
    host.windowVisible = true
    #expect(host.animating)
    host.reduceMotion = true
    #expect(host.animating == false)
    host.reduceMotion = false
    #expect(host.animating)
    host.windowVisible = false
    #expect(host.animating == false)
}

@MainActor @Test func theGlyphHostFollowsTheSameGating() {
    let host = RingHostView(symbol: "arrow.triangle.2.circlepath", diameter: 10)
    #expect(host.layer?.sublayers?.first?.contents != nil)
    #expect(host.animating == false)
    host.windowVisible = true
    #expect(host.animating)
    host.reduceMotion = true
    #expect(host.animating == false)
    host.reduceMotion = false
    host.windowVisible = false
    #expect(host.animating == false)
}

@MainActor @Test(arguments: [EpicMenuState.needsYou, .running, .waiting, .ready])
func everyStateDrawsAGlyph(state: EpicMenuState) throws {
    let renderer = ImageRenderer(content: StateGlyph(state: state))
    renderer.scale = 2
    let image = try #require(renderer.cgImage)
    #expect(image.width == 40 && image.height == 40)
}
