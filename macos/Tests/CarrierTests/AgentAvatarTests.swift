import AppKit
import SwiftUI
import Testing
import CarrierCore
@testable import Carrier

@MainActor @Test func theAvatarTurnsItsRingOnlyForARunningSessionAndUsesTheRingComponent() throws {
    let view = RunningAvatar(initial: "C", running: true)
    #expect(view.ring?.diameter == 22)
    #expect(RunningAvatar(initial: "C", running: false).ring == nil)
}
