import Foundation

// Where a dictation of the widget goes (docs/specs/global-dictation.md, Decisions): a pure function of what the system says about the focus and the
// permission, so it is tested without a screen. `Carrier/FocusedField.swift` reads the focus and the app acts on the answer.

/// What has the cursor in the app in front.
public enum FocusedElement: Equatable, Sendable { case editable, secure, none }

/// Why a text is only copied.
public enum PasteReason: Equatable, Sendable { case noField, noPermission, secureField }

public enum PasteDecision: Equatable, Sendable { case paste, copyOnly(PasteReason) }

/// `focus` is nil when it could not be read, which is what an app without the permission gets.
public func pasteDecision(focus: FocusedElement?, trusted: Bool) -> PasteDecision {
    guard trusted, let focus else { return .copyOnly(.noPermission) }
    switch focus {
    case .editable: return .paste
    case .secure: return .copyOnly(.secureField)
    case .none: return .copyOnly(.noField)
    }
}

extension PasteReason {
    /// What the widget says when the text was only copied.
    public var explanation: String {
        switch self {
        case .noField: "No text field has the cursor, so the text was not pasted."
        case .noPermission: "Accessibility is off for Carrier, or macOS dropped it when the app updated, so the text was not pasted."
        case .secureField: "The field is secure, so the text was not pasted."
        }
    }
}

/// What an element of another app is, from its accessibility role and subrole (docs/research/global-dictation-input.md): a text field, area or
/// combo box whose value can be set (or that has a selection) takes text, a secure text field never gets it, anything else is no field.
public func focusedElement(role: String?, subrole: String?, takesText: Bool) -> FocusedElement {
    if subrole == "AXSecureTextField" { return .secure }
    guard let role, ["AXTextField", "AXTextArea", "AXComboBox"].contains(role), takesText else { return .none }
    return .editable
}
