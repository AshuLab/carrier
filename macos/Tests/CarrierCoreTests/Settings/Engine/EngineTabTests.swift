import Testing
@testable import CarrierCore

@Test func nothingMissingIsAGreenBanner() {
    let banner = readinessBanner(missing: [], detecting: false, bundle: english.bundle, locale: english.locale)
    #expect(banner.state == .ready)
    #expect(banner.title == "Start Carrier is ready")
}

@Test func whatIsMissingIsNamedInTheBanner() {
    #expect(readinessBanner(missing: ["carrier"], detecting: false, bundle: english.bundle, locale: english.locale).state == .missing)
    #expect(readinessBanner(missing: ["carrier"], detecting: false, bundle: english.bundle, locale: english.locale).title == "Start Carrier needs carrier")
    #expect(readinessBanner(missing: ["node"], detecting: false, bundle: english.bundle, locale: english.locale).title == "Start Carrier needs node")
}

@Test func whileDetectingTheBannerSaysSoWhateverIsMissing() {
    #expect(readinessBanner(missing: [], detecting: true, bundle: english.bundle, locale: english.locale).state == .detecting)
    #expect(readinessBanner(missing: ["carrier"], detecting: true, bundle: english.bundle, locale: english.locale).state == .detecting)
}

@Test func whenSomethingIsMissingTheBannerPointsToProgramsOnTheEnginePage() {
    let detail = readinessBanner(missing: ["carrier"], detecting: false, bundle: english.bundle, locale: english.locale).detail
    #expect(detail == "Install carrier with Homebrew, or use “Use another…” and then Detect under Programs on the Engine page.")
}
