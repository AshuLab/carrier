import Foundation
import Testing
@testable import CarrierCore

// The icon, color and label of an account: read from providers.json (a value the engine would refuse reads as absent), edited with the other
// fields of the account and written back, or removed when emptied.

private let file = Data(#"""
{"providers":{
  "claude":{"harness":"claude"},
  "claude-pro":{"harness":"claude","label":" Pro ","color":"orange","icon":"bolt"},
  "claude-teams":{"harness":"claude","label":"Teams","color":"blue","icon":"people","launchArgs":["--chrome"]},
  "odd":{"harness":"codex","label":"far too long a label","color":"mauve","icon":"banana"}
}}
"""#.utf8)

@Test func theIdentityOfEachAccountIsReadAndAnAccountWithNoneIsLeftOut() {
    let found = providerIdentities(providersJSON: file)
    #expect(found["claude"] == nil && found["odd"] == nil)
    #expect(found["claude-pro"] == ProviderIdentity(icon: .bolt, color: .orange, label: "Pro"))
    #expect(found["claude-teams"] == ProviderIdentity(icon: .people, color: .blue, label: "Teams"))
    #expect(providerIdentities(providersJSON: nil).isEmpty)
}

@Test func everyColorAndIconOfTheSchemaIsKnownAndOnlyLetterHasNoSymbol() {
    #expect(AccountColor.allCases.map(\.rawValue) == ["red", "orange", "yellow", "green", "teal", "blue", "purple", "pink"])
    #expect(AccountIcon.allCases.map(\.rawValue) == ["bolt", "star", "briefcase", "person", "people", "code", "flask", "leaf", "moon", "heart", "cube", "letter"])
    #expect(AccountIcon.allCases.filter { $0.symbol == nil } == [.letter])
}

@Test func theEditorStartsFromTheFileAndWritesTheThreeKeysBackNextToTheOnesItDoesNotKnow() throws {
    var draft = try #require(accountDraft(named: "claude-teams", in: file))
    #expect(draft.label == "Teams" && draft.icon == .people && draft.color == .blue)
    draft.label = "  Crew "
    draft.color = .green
    draft.icon = nil
    let written = try applyingEdit(name: "claude-teams", draft: draft, to: file)
    let account = try #require(((try JSONSerialization.jsonObject(with: written) as? [String: Any])?["providers"] as? [String: [String: Any]])?["claude-teams"])
    #expect(account["label"] as? String == "Crew" && account["color"] as? String == "green")
    #expect(account["icon"] == nil, "the tool's own mark is no key")
    #expect(account["launchArgs"] as? [String] == ["--chrome"])
}

@Test func anEmptiedLabelRemovesTheKey() throws {
    var draft = try #require(accountDraft(named: "claude-pro", in: file))
    draft.label = "   "
    let written = try applyingEdit(name: "claude-pro", draft: draft, to: file)
    let account = try #require(((try JSONSerialization.jsonObject(with: written) as? [String: Any])?["providers"] as? [String: [String: Any]])?["claude-pro"])
    #expect(account["label"] == nil && account["color"] as? String == "orange")
}

@Test func aLabelLongerThanTheLimitOrOfSeveralLinesIsRefusedByItsKey() {
    var draft = AccountDraft()
    draft.label = String(repeating: "x", count: ProviderIdentity.labelLimit)
    #expect(draftProblems(draft, harness: "claude")["label"] == nil)
    draft.label += "x"
    #expect(draftProblems(draft, harness: "claude")["label"] != nil)
    draft.label = "a\nb"
    #expect(draftProblems(draft, harness: "claude")["label"] != nil)
}
