import Testing

@testable import CarrierCore

@Test func aSheetTakesThreeQuartersOfTheWindowWithinItsFloorAndTheWindow() {
    #expect(sheetSize(windowWidth: 1100, windowHeight: 600) == (825, 560))
    #expect(sheetSize(windowWidth: 1600, windowHeight: 1000) == (1200, 750))
    // a window smaller than the floor still leaves a margin around the sheet
    #expect(sheetSize(windowWidth: 700, windowHeight: 500) == (660, 460))
    // a capped sheet stops growing in width, not in height
    #expect(sheetSize(windowWidth: 2400, windowHeight: 1400, maxWidth: 1300) == (1300, 1050))
    #expect(sheetSize(windowWidth: 1600, windowHeight: 1000, maxWidth: 1300) == (1200, 750))
}
