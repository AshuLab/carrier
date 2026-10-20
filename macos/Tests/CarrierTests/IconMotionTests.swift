import Foundation
import QuartzCore
import Testing
@testable import Carrier

@Test func theBounceIsCappedAt20FpsAndRepeatsByItself() throws {
    let layer = CALayer()
    IconController.bounce(layer, travel: 5)
    let bounce = try #require(layer.animation(forKey: "bounce") as? CABasicAnimation)
    #expect(bounce.preferredFrameRateRange == CAFrameRateRange(minimum: 20, maximum: 20, preferred: 20))
    // Core Animation repeats it in the render server, nothing in the app ticks it
    #expect(bounce.repeatCount == .infinity)
    #expect(bounce.autoreverses)
    #expect(bounce.toValue as? Double == 5)
}

@Test func noTravelLeavesNoAnimationAndANewOneReplacesTheOld() throws {
    let layer = CALayer()
    IconController.bounce(layer, travel: 5)
    IconController.bounce(layer, travel: 9)
    #expect(layer.animationKeys() == ["bounce"])
    #expect(try #require(layer.animation(forKey: "bounce") as? CABasicAnimation).toValue as? Double == 9)
    IconController.bounce(layer, travel: nil)
    #expect(layer.animationKeys() == nil)
}

@Test func theIconHasNoTimerOrDisplayLink() throws {
    let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/Carrier/IconController.swift")
    let code = try String(contentsOf: source, encoding: .utf8)
    for forbidden in ["Timer", "CADisplayLink", "asyncAfter"] {
        #expect(!code.contains(forbidden), "IconController uses \(forbidden)")
    }
}
