import AppKit
import CarrierCore
import SwiftUI
import Testing
@testable import Carrier

private let steps: [PipelineStep] = {
    let json = #"{"repo":"acme/web","issue":12,"status":"needs_human","needsHumanKind":"review_limit","stage":"review","round":5,"maxReviews":5,"blockers":0,"stageSince":0,"issueUrl":""}"#
    return pipelineSteps(.active(try! JSONDecoder().decode(PanelEpic.self, from: Data(json.utf8))))
}()

/// The height of the strip drawn at `width` points.
@MainActor private func height(at width: CGFloat) throws -> Int {
    let renderer = ImageRenderer(content: PipelineStrip(steps: steps).frame(width: width))
    renderer.scale = 2
    return try #require(renderer.cgImage).height
}

// A wrapped line would make the strip taller: it stays as high as when there is room, down to the narrowest centre column.
@MainActor @Test(arguments: [CGFloat(340), 420, 560])
func thePipelineStaysOnOneLineWhateverTheWidth(width: CGFloat) throws {
    #expect(try height(at: width) == height(at: 1200))
}
