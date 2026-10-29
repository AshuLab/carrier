import Testing
@testable import CarrierCore

@Test func anOlderHostIsReplacedWhenNoSessionIsWorking() {
    #expect(hostReplacement(running: "0.1.0", installed: "0.2.0", working: false) == .replace)
    #expect(hostReplacement(running: "0.9.0", installed: "0.10.0", working: false) == .replace)
    #expect(hostReplacement(running: "1.2", installed: "1.2.1", working: false) == .replace)
}

@Test func anOlderHostWithASessionWorkingAsksForARestart() {
    #expect(hostReplacement(running: "0.1.0", installed: "0.2.0", working: true) == .askRestart)
}

@Test func anEqualOrNewerHostStays() {
    #expect(hostReplacement(running: "0.2.0", installed: "0.2.0", working: false) == .keep)
    #expect(hostReplacement(running: "1.2", installed: "1.2.0", working: false) == .keep)
    #expect(hostReplacement(running: "0.3.0", installed: "0.2.0", working: false) == .keep)
    #expect(hostReplacement(running: "0.3.0", installed: "0.2.0", working: true) == .keep)
}

@Test func aVersionThatIsNotNumbersSeparatedByDotsStays() {
    for bad in ["", "unknown", "1.2-beta", "1..2", ".1", "1.", "v1.2", "1.٣"] {
        #expect(hostReplacement(running: bad, installed: "9.0.0", working: false) == .keep)
        #expect(hostReplacement(running: "0.1.0", installed: bad, working: false) == .keep)
        #expect(hostReplacement(running: "0.1.0", installed: bad, working: true) == .keep)
    }
}

@Test func theLineCarrierPrintsReadsAsItIs() {
    #expect(versionNumbers("0.1.0\n") == [0, 1, 0])
    #expect(versionNumbers("usage: carrier") == nil)
}
