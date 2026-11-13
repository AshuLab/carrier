import Testing
@testable import CarrierCore

@Test func nothingMissingIsAGreenBanner() {
    let banner = readinessBanner(missing: [], detecting: false)
    #expect(banner.state == .ready)
    #expect(banner.title == "Start Carrier is ready")
}

@Test func whatIsMissingIsNamedInTheBanner() {
    #expect(readinessBanner(missing: ["carrier"], detecting: false).state == .missing)
    #expect(readinessBanner(missing: ["carrier"], detecting: false).title == "Start Carrier needs carrier")
    #expect(readinessBanner(missing: ["node"], detecting: false).title == "Start Carrier needs node")
}

@Test func whileDetectingTheBannerSaysSoWhateverIsMissing() {
    #expect(readinessBanner(missing: [], detecting: true).state == .detecting)
    #expect(readinessBanner(missing: ["carrier"], detecting: true).state == .detecting)
}

@Test func whenSomethingIsMissingTheBannerPointsToProgramsOnTheEnginePage() {
    let detail = readinessBanner(missing: ["carrier"], detecting: false).detail
    #expect(detail == "Install carrier with Homebrew, or use “Use another…” and then Detect under Programs.")
}
