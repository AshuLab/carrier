import AppKit
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
    #expect(AccountColor.allCases.map(\.rawValue) == ["red", "orange", "yellow", "green", "teal", "blue", "purple", "pink", "mint", "cyan", "indigo", "brown", "gray"])
    #expect(AccountIcon.allCases.map(\.rawValue) == [
        "bolt", "star", "briefcase", "person", "people", "code", "flask", "leaf", "moon", "heart", "cube", "letter",
        "flame", "sparkles", "paperplane", "globe", "shield", "key", "house", "book", "hammer", "cloud", "bell",
    ])
    #expect(AccountIcon.allCases.filter { $0.symbol == nil } == [.letter])
}

@Test func theEditorStartsFromTheLabelIconAndColorTheFileHas() throws {
    let draft = try #require(accountDraft(named: "claude-teams", in: file))
    #expect(draft.label == "Teams" && draft.icon == .people && draft.color == .blue)
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

@Test func theDisplayNameOfAnAccountIsReadTrimmedAndAnEmptyOneIsNone() {
    let json = Data(#"{"providers":{"pro":{"harness":"claude","displayName":" Claude Pro "},"blank":{"harness":"claude","displayName":"  "},"bare":{"harness":"codex"}}}"#.utf8)
    #expect(providerDisplayNames(providersJSON: json) == ["pro": "Claude Pro"])
    #expect(providerDisplayNames(providersJSON: nil).isEmpty && providerDisplayNames(providersJSON: Data("nope".utf8)).isEmpty)
}

@Test func theLaterIconsAndColorsAreOfferedOnlyToAHostThatKnowsThem() {
    #expect(AccountIcon.offered(palette: false) == [.bolt, .star, .briefcase, .person, .people, .code, .flask, .leaf, .moon, .heart, .cube, .letter])
    #expect(AccountColor.offered(palette: false) == [.red, .orange, .yellow, .green, .teal, .blue, .purple, .pink])
    #expect(AccountIcon.offered(palette: true) == AccountIcon.allCases && AccountColor.offered(palette: true) == AccountColor.allCases)
    // every glyph is a symbol this system has; only the letter has none
    #expect(AccountIcon.allCases.filter { $0.symbol == nil } == [.letter])
    #expect(AccountIcon.allCases.compactMap(\.symbol).allSatisfy { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil })
    // a later value in the file is read, so a session drawn from it shows it
    let identity = providerIdentities(providersJSON: Data(#"{"providers":{"a":{"harness":"claude","icon":"flame","color":"indigo"}}}"#.utf8))
    #expect(identity["a"] == ProviderIdentity(icon: .flame, color: .indigo))
}

@Test func anAccountIsNamedShortByItsLabelElseItsDisplayNameElseItsOwnName() {
    let identities = ["claude-pro": ProviderIdentity(label: "Pro"), "codex-work": ProviderIdentity(icon: .bolt)]
    let names = ["claude-pro": "Claude Pro account", "codex-work": "Codex at work"]
    #expect(providerShortName(of: "claude-pro", identities: identities, displayNames: names) == "Pro")
    #expect(providerShortName(of: "codex-work", identities: identities, displayNames: names) == "Codex at work")
    #expect(providerShortName(of: "gemini", identities: identities, displayNames: names) == "gemini")
}

@Test func theMarkOfAnAccountIsItsGlyphItsLetterOrItsToolsMarkInItsColor() {
    let glyph = accountMarkLook(of: "claude-pro", identity: ProviderIdentity(icon: .bolt, color: .orange, label: "Pro"))
    #expect(glyph == AccountMarkLook(symbol: "bolt", initials: "", tool: AgentAccounts.harness(of: "claude-pro"), color: .orange))
    let letter = accountMarkLook(of: "teams", identity: ProviderIdentity(icon: .letter, color: .blue))
    #expect(letter.symbol == nil && letter.initials == "T" && letter.color == .blue)
    // an account with no icon wears its tool's mark: the one asked for when given, else the agent's harness
    let none = accountMarkLook(of: "acct", identity: .none, icon: "codex")
    #expect(none == AccountMarkLook(symbol: nil, initials: "", tool: "codex", color: nil))
}
