import CarrierCore
import Foundation
import IOKit.pwr_mgt
import Testing
@testable import Carrier

/// What the system itself says this process holds, by the type of the assertions the adapter takes: a hold that was never let go shows here
/// even when the adapter believes it let go.
private func assertionsHeldBySystem() -> [String] {
    var byProcess: Unmanaged<CFDictionary>?
    guard IOPMCopyAssertionsByProcess(&byProcess) == kIOReturnSuccess, let all = byProcess?.takeRetainedValue() as? [Int: [[String: Any]]] else { return [] }
    return (all[Int(getpid())] ?? []).compactMap { $0[kIOPMAssertionTypeKey as String] as? String }
        .filter { $0 == kIOPMAssertPreventUserIdleSystemSleep as String || $0 == kIOPMAssertPreventUserIdleDisplaySleep as String }
}

@Test @MainActor func theRealAssertionsAreHeldAndLetGoAsTheSystemSaysForTheProcess() {
    let assertion = SystemKeepAwakeAssertion()
    defer {
        assertion.release(.system)
        assertion.release(.display)
    }
    #expect(assertionsHeldBySystem().isEmpty)
    #expect(assertion.take(.system))
    #expect(assertion.isHeld(.system) && assertion.isHeld(.display) == false)
    #expect(assertionsHeldBySystem() == [kIOPMAssertPreventUserIdleSystemSleep as String])
    // taking it again keeps the one it has
    #expect(assertion.take(.system))
    #expect(assertionsHeldBySystem().count == 1)
    #expect(assertion.take(.display))
    #expect(Set(assertionsHeldBySystem()) == [kIOPMAssertPreventUserIdleSystemSleep as String, kIOPMAssertPreventUserIdleDisplaySleep as String])
    assertion.release(.system)
    assertion.release(.display)
    #expect(assertion.isHeld(.system) == false && assertion.isHeld(.display) == false)
    #expect(assertionsHeldBySystem().isEmpty)
}
