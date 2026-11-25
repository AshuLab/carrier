import Foundation
import Observation

/// What a Dictation view shows of Accessibility: what macOS said the last time it was asked. Asked again with `refresh`, each time Carrier comes back to the
/// front, since the person allows it in System Settings.
@MainActor @Observable public final class AccessibilityState {
    public private(set) var trusted: Bool
    @ObservationIgnored private let trust: any AccessibilityTrust

    public init(trust: any AccessibilityTrust) {
        self.trust = trust
        trusted = trust.isTrusted()
    }

    public func refresh() { trusted = trust.isTrusted() }

    /// macOS asks the person; the answer comes with the next `refresh`.
    public func ask() { trust.prompt() }

    /// Whether turning the global switch on first explains what Accessibility is for (`shouldExplainAccessibility`), by what macOS says now.
    public func shouldExplain(explained: Bool) -> Bool {
        shouldExplainAccessibility(explained: explained, trusted: trust.isTrusted())
    }
}
