import ApplicationServices
import CarrierCore

/// `AccessibilityTrust` on `AXIsProcessTrusted`.
struct SystemAccessibilityTrust: AccessibilityTrust {
    func isTrusted() -> Bool { AXIsProcessTrusted() }

    func prompt() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }
}
