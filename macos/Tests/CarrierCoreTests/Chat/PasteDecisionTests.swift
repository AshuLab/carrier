import Testing
@testable import CarrierCore

@Test func aTrustedAppPastesOnlyIntoAnEditableField() {
    #expect(pasteDecision(focus: .editable, trusted: true) == .paste)
    #expect(pasteDecision(focus: .secure, trusted: true) == .copyOnly(.secureField))
    #expect(pasteDecision(focus: FocusedElement.none, trusted: true) == .copyOnly(.noField))
}

@Test func withoutThePermissionOrAReadableFocusItIsNeverAPaste() {
    for focus in [FocusedElement.editable, .secure, FocusedElement.none, nil] {
        #expect(pasteDecision(focus: focus, trusted: false) == .copyOnly(.noPermission))
    }
    #expect(pasteDecision(focus: nil, trusted: true) == .copyOnly(.noPermission))
}

@Test func everyReasonSaysWhyInItsOwnWords() {
    let words = [PasteReason.noField, .noPermission, .secureField].map(\.explanation)
    #expect(Set(words).count == 3)
    #expect(words[0].contains("text field") && words[1].contains("Accessibility") && words[2].contains("secure"))
}

@Test(arguments: [
    ("AXTextField", nil, true, FocusedElement.editable), ("AXTextArea", "AXSearchField", true, .editable), ("AXComboBox", nil, true, .editable),
    ("AXTextField", "AXSecureTextField", true, .secure), ("AXTextField", "AXSecureTextField", false, .secure),
    ("AXTextArea", nil, false, FocusedElement.none), ("AXButton", nil, true, .none), ("AXWebArea", nil, true, .none),
] as [(String?, String?, Bool, FocusedElement)])
func anElementIsAFieldBySubroleAndRoleAndWhetherItTakesText(role: String?, subrole: String?, takesText: Bool, expected: FocusedElement) {
    #expect(focusedElement(role: role, subrole: subrole, takesText: takesText) == expected)
}

@Test func noRoleIsNoField() {
    #expect(focusedElement(role: nil, subrole: nil, takesText: true) == .none)
}
