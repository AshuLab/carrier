import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CarrierCore

/// What the Accessibility permission lets the app see and ask: the field that has the cursor in the app in front, and the pane of System Settings
/// where the person allows it. No automated test: the rule is `pasteDecision` and `focusedElement` (docs/research/global-dictation-input.md).
enum FocusedField {
    static let settingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

    /// Opens Privacy & Security › Accessibility.
    @MainActor static func openSettings() {
        if let url = URL(string: settingsURL) { NSWorkspace.shared.open(url) }
    }

    /// Where a dictation that ends now goes. Never reads the value of the field, which for a password holds the secret.
    static func decision() -> PasteDecision {
        let trusted = AXIsProcessTrusted()
        return pasteDecision(focus: trusted ? read() : nil, trusted: trusted)
    }

    private static func read() -> FocusedElement {
        // a password field has Secure Event Input on, which needs no permission to see and also covers a web password the roles do not show
        guard IsSecureEventInputEnabled() == false else { return .secure }
        var focused: CFTypeRef?
        // any failure here, with the permission, is a field that is not there (a terminal, a web page that exposes nothing)
        guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &focused) == .success,
            let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return .none }
        let element = focused as! AXUIElement
        var settable: DarwinBoolean = false
        let valueSettable = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success && settable.boolValue
        return focusedElement(
            role: text(element, kAXRoleAttribute), subrole: text(element, kAXSubroleAttribute),
            takesText: valueSettable || has(element, kAXSelectedTextRangeAttribute))
    }

    private static func text(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func has(_ element: AXUIElement, _ attribute: String) -> Bool {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
    }
}
