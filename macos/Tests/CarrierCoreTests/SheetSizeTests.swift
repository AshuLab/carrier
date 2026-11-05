import Testing

@testable import CarrierCore

@Test func aSheetTakesThreeQuartersOfTheWindowWithinItsFloorAndTheWindow() {
    #expect(sheetSize(windowWidth: 1100, windowHeight: 600) == (825, 560))
    #expect(sheetSize(windowWidth: 1600, windowHeight: 1000) == (1200, 750))
    // a window smaller than the floor still leaves a margin around the sheet
    #expect(sheetSize(windowWidth: 700, windowHeight: 500) == (660, 460))
}
