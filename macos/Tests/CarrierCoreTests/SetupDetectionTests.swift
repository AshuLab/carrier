import Foundation
import Testing
@testable import CarrierCore

private let answer = """
    \(detectionBegin)
    carrier=/Users/ana/.nvm/versions/node/v26/bin/carrier
    node=/Users/ana/.nvm/versions/node/v26/bin/node
    path=/Users/ana/.nvm/versions/node/v26/bin:/usr/bin:/bin
    \(detectionEnd)
    """

@Test func theAnswerBetweenTheMarkersIsRead() {
    #expect(parseDetection(answer) == Detection(
        carrier: "/Users/ana/.nvm/versions/node/v26/bin/carrier",
        node: "/Users/ana/.nvm/versions/node/v26/bin/node",
        path: "/Users/ana/.nvm/versions/node/v26/bin:/usr/bin:/bin"
    ))
}

@Test func noiseBeforeAndAfterTheMarkersIsIgnored() {
    let noisy = "Welcome back, ana\npath=/wrong\nnode=/wrong/node\n" + answer + "\nbye\nnode=/also/wrong\n"
    #expect(parseDetection(noisy) == parseDetection(answer))
}

@Test func aToolThatWasNotFoundIsNil() {
    let output = "\(detectionBegin)\ncarrier=\nnode=/usr/local/bin/node\npath=/usr/local/bin:/usr/bin\n\(detectionEnd)\n"
    #expect(parseDetection(output) == Detection(carrier: nil, node: "/usr/local/bin/node", path: "/usr/local/bin:/usr/bin"))
}

@Test func anAliasOrAFunctionIsNotATool() {
    // `command -v` prints the word or the definition for those, not a path
    let output = "\(detectionBegin)\ncarrier=carrier\nnode=alias node=nvm\npath=/usr/bin\n\(detectionEnd)\n"
    #expect(parseDetection(output) == Detection(carrier: nil, node: nil, path: "/usr/bin"))
}

@Test func anEmptyOutputIsNoAnswer() {
    #expect(parseDetection("") == nil)
    #expect(parseDetection("\n\n") == nil)
}

@Test func aShellThatHitTheLimitIsNoAnswer() {
    // killed before it printed the end marker, or before it printed anything but the banner
    #expect(parseDetection("\(detectionBegin)\ncarrier=/usr/bin/carrier\nnode=/usr/bin/node\n") == nil)
    #expect(parseDetection("Loading plugins...\n") == nil)
    #expect(parseDetection("\(detectionEnd)\n\(detectionBegin)\nnode=/usr/bin/node\n") == nil)
}

@Test func markersWithNothingInsideFindNothing() {
    #expect(parseDetection("\(detectionBegin)\n\(detectionEnd)\n") == Detection())
}

@Test func theScriptPrintsTheMarkersAndTheThreeLines() {
    #expect(detectionScript.contains(detectionBegin) && detectionScript.contains(detectionEnd))
    for key in ["carrier=", "node=", "path="] { #expect(detectionScript.contains(key)) }
}

@Test func nodesFolderGoesFirstWhenItIsNotThere() {
    #expect(enginePath(detected: "/usr/local/bin:/usr/bin", node: "/Users/ana/.nvm/bin/node") == "/Users/ana/.nvm/bin:/usr/local/bin:/usr/bin")
}

@Test func nodesFolderAlreadyFirstIsLeftAlone() {
    #expect(enginePath(detected: "/Users/ana/.nvm/bin:/usr/bin", node: "/Users/ana/.nvm/bin/node") == "/Users/ana/.nvm/bin:/usr/bin")
}

@Test func nodesFolderFurtherDownMovesToTheFront() {
    #expect(enginePath(detected: "/usr/bin:/Users/ana/.nvm/bin:/bin", node: "/Users/ana/.nvm/bin/node") == "/Users/ana/.nvm/bin:/usr/bin:/bin")
}

@Test func noNodeLeavesThePathAsDetected() {
    #expect(enginePath(detected: "/usr/bin:/bin", node: "") == "/usr/bin:/bin")
    #expect(enginePath(detected: "/usr/bin:/bin", node: "node") == "/usr/bin:/bin")
}

@Test func anEmptyPathIsJustNodesFolder() {
    #expect(enginePath(detected: "", node: "/Users/ana/.nvm/bin/node") == "/Users/ana/.nvm/bin")
    #expect(enginePath(detected: "", node: "") == "")
}

@Test func theSettingsHaveNoConfigPathAndEmptyOnesAreListedAsMissing() {
    #expect(SetupSettings().missing == ["carrier", "node", "PATH"])
    #expect(SetupSettings(carrier: "/bin/carrier", node: "/bin/node", path: "/bin").missing.isEmpty)
}

@Test func aConfigPathSavedByAnOlderAppIsIgnoredAndDroppedOnTheNextSave() {
    let (defaults, name) = freshDefaults()
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set(["carrier": "/c", "node": "/n", "path": "/p", "configPath": "/old/config.json"], forKey: "setup")
    let store = SetupStore(defaults: defaults)
    #expect(store.load() == SetupSettings(carrier: "/c", node: "/n", path: "/p"))
    store.save(store.load()!)
    #expect(defaults.dictionary(forKey: "setup")?.keys.sorted() == ["carrier", "node", "path"])
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

    let edited = SetupSettings(carrier: "/c", node: "/n", path: "/p")
    store.save(edited)
    #expect(store.load() == edited)
}
