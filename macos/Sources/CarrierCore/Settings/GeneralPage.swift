import Foundation

/// The words of the General page: its two groups, the rows with the line under each, and the choices the two pop-ups offer.
public struct GeneralPage: Equatable, Sendable {
    public let menuBar: String
    public let iconStyle: PageRowText
    public let animate: PageRowText
    public let listEpics: PageRowText
    public let display: String
    public let timeFormat: PageRowText
    public let clock: PageRowText
    public let relative: String
    public let clockOption: String
    public let system: String
    public let hours12: String
    public let hours24: String
}

public func generalPage(bundle: Bundle? = nil, locale: Locale = .current) -> GeneralPage {
    GeneralPage(
        menuBar: Copy.generalMenuBar(bundle: bundle, locale: locale),
        iconStyle: PageRowText(title: Copy.generalIconStyle(bundle: bundle, locale: locale), detail: Copy.generalIconStyleDetail(bundle: bundle, locale: locale)),
        animate: PageRowText(title: Copy.generalAnimate(bundle: bundle, locale: locale), detail: Copy.generalAnimateDetail(bundle: bundle, locale: locale)),
        listEpics: PageRowText(title: Copy.generalListEpics(bundle: bundle, locale: locale), detail: Copy.generalListEpicsDetail(bundle: bundle, locale: locale)),
        display: Copy.generalDisplay(bundle: bundle, locale: locale),
        timeFormat: PageRowText(title: Copy.generalTimeFormat(bundle: bundle, locale: locale), detail: Copy.generalTimeFormatDetail(bundle: bundle, locale: locale)),
        clock: PageRowText(title: Copy.generalClock(bundle: bundle, locale: locale), detail: Copy.generalClockDetail(bundle: bundle, locale: locale)),
        relative: Copy.generalTimeRelative(bundle: bundle, locale: locale),
        clockOption: Copy.generalTimeClock(bundle: bundle, locale: locale),
        system: Copy.generalClockSystem(bundle: bundle, locale: locale),
        hours12: Copy.generalClock12(bundle: bundle, locale: locale),
        hours24: Copy.generalClock24(bundle: bundle, locale: locale))
}
