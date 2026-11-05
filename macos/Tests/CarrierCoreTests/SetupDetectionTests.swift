import Foundation
import Testing
@testable import CarrierCore

private let answer = """
    \(detectionBegin)
    node=/Users/ana/.nvm/versions/node/v26/bin/node
    path=/Users/ana/.nvm/versions/node/v26/bin:/usr/bin:/bin
    \(detectionEnd)
    """

@Test func theAnswerBetweenTheMarkersIsRead() {
    #expect(parseDetection(answer) == Detection(
        node: "/Users/ana/.nvm/versions/node/v26/bin/node",
        path: "/Users/ana/.nvm/versions/node/v26/bin:/usr/bin:/bin"
    ))
}

@Test func noiseBeforeAndAfterTheMarkersIsIgnored() {
    let noisy = "Welcome back, ana\npath=/wrong\nnode=/wrong/node\n" + answer + "\nbye\nnode=/also/wrong\n"
    #expect(parseDetection(noisy) == parseDetection(answer))
}

@Test func aToolThatWasNotFoundIsNil() {
    let output = "\(detectionBegin)\nnode=\npath=/usr/local/bin:/usr/bin\n\(detectionEnd)\n"
    #expect(parseDetection(output) == Detection(node: nil, path: "/usr/local/bin:/usr/bin"))
}

@Test func anAliasOrAFunctionIsNotATool() {
    // `command -v` prints the word or the definition for those, not a path
    let output = "\(detectionBegin)\nnode=alias node=nvm\npath=/usr/bin\n\(detectionEnd)\n"
    #expect(parseDetection(output) == Detection(node: nil, path: "/usr/bin"))
}

@Test func aCarrierLineIsNotReadAnyMore() {
    let output = "\(detectionBegin)\ncarrier=/opt/x/carrier\nnode=/usr/bin/node\npath=/usr/bin\n\(detectionEnd)\n"
    #expect(parseDetection(output) == Detection(node: "/usr/bin/node", path: "/usr/bin"))
}

@Test func anEmptyOutputIsNoAnswer() {
    #expect(parseDetection("") == nil)
    #expect(parseDetection("\n\n") == nil)
}

@Test func aShellThatHitTheLimitIsNoAnswer() {
    // killed before it printed the end marker, or before it printed anything but the banner
    #expect(parseDetection("\(detectionBegin)\nnode=/usr/bin/node\n") == nil)
    #expect(parseDetection("Loading plugins...\n") == nil)
    #expect(parseDetection("\(detectionEnd)\n\(detectionBegin)\nnode=/usr/bin/node\n") == nil)
}

@Test func markersWithNothingInsideFindNothing() {
    #expect(parseDetection("\(detectionBegin)\n\(detectionEnd)\n") == Detection())
}

@Test func theScriptPrintsTheMarkersAndTheTwoLines() {
    #expect(detectionScript.contains(detectionBegin) && detectionScript.contains(detectionEnd))
    for key in ["node=", "path="] { #expect(detectionScript.contains(key)) }
    #expect(detectionScript.contains("carrier") == false)
}

@Test func nodesFolderGoesFirstWhenItIsNotThere() {
    #expect(enginePath(detected: "/usr/local/bin:/usr/bin", node: "/Users/ana/.nvm/bin/node") == "/Users/ana/.nvm/bin:/usr/local/bin:/usr/bin:/opt/homebrew/bin")
}

@Test func nodesFolderAlreadyFirstIsLeftAlone() {
    #expect(enginePath(detected: "/Users/ana/.nvm/bin:/usr/bin", node: "/Users/ana/.nvm/bin/node") == "/Users/ana/.nvm/bin:/usr/bin:/opt/homebrew/bin")
}

@Test func nodesFolderFurtherDownMovesToTheFront() {
    #expect(enginePath(detected: "/usr/bin:/Users/ana/.nvm/bin:/bin", node: "/Users/ana/.nvm/bin/node") == "/Users/ana/.nvm/bin:/usr/bin:/bin:/opt/homebrew/bin")
}

@Test func noNodeLeavesThePathAsDetectedPlusHomebrew() {
    #expect(enginePath(detected: "/usr/bin:/bin", node: "") == "/usr/bin:/bin:/opt/homebrew/bin")
    #expect(enginePath(detected: "/usr/bin:/bin", node: "node") == "/usr/bin:/bin:/opt/homebrew/bin")
}

@Test func anEmptyPathIsNodesFolderAndHomebrew() {
    #expect(enginePath(detected: "", node: "/Users/ana/.nvm/bin/node") == "/Users/ana/.nvm/bin:/opt/homebrew/bin")
    #expect(enginePath(detected: "", node: "") == "/opt/homebrew/bin")
}

@Test func homebrewIsAddedAtTheEndOnceAndLeftWhereItWas() {
    #expect(enginePath(detected: "/usr/bin", node: "") == "/usr/bin:/opt/homebrew/bin")
    #expect(enginePath(detected: "/opt/homebrew/bin:/usr/bin", node: "") == "/opt/homebrew/bin:/usr/bin")
    #expect(enginePath(detected: "/usr/bin:/opt/homebrew/bin:/bin", node: "") == "/usr/bin:/opt/homebrew/bin:/bin")
    // node from Homebrew: its folder goes first and is not added a second time
    #expect(enginePath(detected: "/usr/bin:/opt/homebrew/bin", node: "/opt/homebrew/bin/node") == "/opt/homebrew/bin:/usr/bin")
}

@Test func theHomebrewCarrierIsUsedWhenThereIsNoOverrideAndItIsExecutable() {
    #expect(carrierPath(override: "", isExecutable: { $0 == "/opt/homebrew/bin/carrier" }) == "/opt/homebrew/bin/carrier")
    #expect(carrierPath(override: "", isExecutable: { _ in false }) == nil)
}

@Test func aBlankOverrideCountsAsNotSet() {
    #expect(carrierPath(override: "  \n\t ", isExecutable: { _ in true }) == "/opt/homebrew/bin/carrier")
    #expect(carrierPath(override: "   ", isExecutable: { _ in false }) == nil)
}

@Test func anOverrideIsTrimmedAndTakenAsTypedWithoutAskingTheDisk() {
    #expect(carrierPath(override: "  /work/carrier/main.ts \n", isExecutable: { _ in Issue.record("asked"); return false }) == "/work/carrier/main.ts")
}

@Test func aScriptRunsUnderNodeAndAnythingElseRunsItself() {
    #expect(carrierProgram(carrier: "/work/main.ts", node: "/n/node", arguments: ["chat-host"]) == ("/n/node", ["/work/main.ts", "chat-host"]))
    #expect(carrierProgram(carrier: "/work/main.js", node: "/n/node", arguments: []) == ("/n/node", ["/work/main.js"]))
    #expect(carrierProgram(carrier: "/opt/homebrew/bin/carrier", node: "/n/node", arguments: ["chat-host"]) == ("/opt/homebrew/bin/carrier", ["chat-host"]))
}

@Test func emptyShellValuesAreListedAsMissing() {
    #expect(SetupSettings().missing == ["node", "PATH"])
    #expect(SetupSettings(node: "/bin/node", path: "/bin").missing.isEmpty)
}

@Test func whatTheThreeFieldSetupSavedIsIgnored() {
    let (defaults, name) = freshDefaults()
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set(["carrier": "/c", "node": "/n", "path": "/p"], forKey: "setup")
    let store = SetupStore(defaults: defaults)
    #expect(store.load() == nil)
    #expect(store.carrierOverride.isEmpty)
}

@Test func theOverrideIsSavedApartFromTheShellsValues() {
    let (defaults, name) = freshDefaults()
    defer { defaults.removePersistentDomain(forName: name) }
    let store = SetupStore(defaults: defaults)
    store.carrierOverride = "/work/main.ts"
    #expect(SetupStore(defaults: defaults).carrierOverride == "/work/main.ts")
    #expect(store.load() == nil)
}

private func freshDefaults() -> (UserDefaults, String) {
    let name = "carrier-setup-test-\(UUID().uuidString.prefix(8))"
    return (UserDefaults(suiteName: name)!, name)
}

@Test func nothingSavedMeansFirstLaunchAndSavedValuesComeBack() {
    let (defaults, name) = freshDefaults()
    defer { defaults.removePersistentDomain(forName: name) }
    let store = SetupStore(defaults: defaults)
    #expect(store.load() == nil)

    // a detection that found nothing is saved too: the shell is not asked again by itself
    store.save(SetupSettings())
    #expect(SetupStore(defaults: defaults).load() == SetupSettings())

    let edited = SetupSettings(node: "/n", path: "/p")
    store.save(edited)
    #expect(store.load() == edited)
}
