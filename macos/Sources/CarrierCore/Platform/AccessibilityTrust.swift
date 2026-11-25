import Foundation

/// What macOS says of the Accessibility permission; the app's is `AXIsProcessTrusted` (`Carrier/Platform/SystemAccessibilityTrust.swift`).
public protocol AccessibilityTrust: Sendable {
    /// Whether the person has allowed Carrier in Privacy & Security › Accessibility.
    func isTrusted() -> Bool
    /// Asks macOS, which lists Carrier in Accessibility for the person to allow.
    func prompt()
}
