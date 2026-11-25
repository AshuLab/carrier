import Foundation

/// The words of the Appearance page: its four groups, its rows with the line under each, what the sliders say to VoiceOver and the names of the states the preview shows.
/// The two numbers a line quotes (the text size and the weight of the icons) are the person's current values.
public struct AppearancePage: Equatable, Sendable {
    public let theme: String
    public let look: String
    public let color: String
    public let code: String
    public let colorScheme: PageRowText
    public let textSize: PageRowText
    public let textSizeValue: String
    public let iconSet: PageRowText
    public let iconWeight: PageRowText
    public let iconWeightValue: String
    public let density: PageRowText
    public let byShape: PageRowText
    public let stateWorking: String
    public let stateNeedsAttention: String
    public let stateReady: String
    public let stateProblem: String
    public let accent: PageRowText
    public let tint: PageRowText
    public let translucent: PageRowText
    public let font: PageRowText
    public let size: PageRowText
    public let codeSize: String
    public let codeSizeValue: String
    public let lineHeight: PageRowText
    public let ligatures: PageRowText
    public let wrap: PageRowText
    public let lineNumbers: PageRowText
}

/// `iconWeight` is written with up to two decimals in the language of `locale`.
public func appearancePage(textSize: Int, iconWeight: Double, codeSize: Int, bundle: Bundle? = nil, locale: Locale = .current) -> AppearancePage {
    let weight = iconWeight.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
    func row(_ title: String, _ detail: String) -> PageRowText { PageRowText(title: title, detail: detail) }
    let groups = (
        Copy.appearanceTheme(bundle: bundle, locale: locale), Copy.appearanceLook(bundle: bundle, locale: locale),
        Copy.appearanceColor(bundle: bundle, locale: locale), Copy.appearanceCode(bundle: bundle, locale: locale))
    let look = (
        row(Copy.appearanceColorScheme(bundle: bundle, locale: locale), Copy.appearanceColorSchemeDetail(bundle: bundle, locale: locale)),
        row(Copy.appearanceTextSize(bundle: bundle, locale: locale), Copy.appearanceTextSizeDetail(size: textSize, bundle: bundle, locale: locale)),
        row(Copy.appearanceIconSet(bundle: bundle, locale: locale), Copy.appearanceIconSetDetail(bundle: bundle, locale: locale)),
        row(Copy.appearanceIconWeight(bundle: bundle, locale: locale), Copy.appearanceIconWeightDetail(weight: weight, bundle: bundle, locale: locale)),
        row(Copy.appearanceDensity(bundle: bundle, locale: locale), Copy.appearanceDensityDetail(bundle: bundle, locale: locale)),
        row(Copy.appearanceByShape(bundle: bundle, locale: locale), Copy.appearanceByShapeDetail(bundle: bundle, locale: locale)))
    let color = (
        row(Copy.appearanceAccent(bundle: bundle, locale: locale), Copy.appearanceAccentDetail(bundle: bundle, locale: locale)),
        row(Copy.appearanceTint(bundle: bundle, locale: locale), Copy.appearanceTintDetail(bundle: bundle, locale: locale)),
        row(Copy.appearanceTranslucent(bundle: bundle, locale: locale), Copy.appearanceTranslucentDetail(bundle: bundle, locale: locale)))
    let code = (
        row(Copy.appearanceFont(bundle: bundle, locale: locale), Copy.appearanceFontDetail(bundle: bundle, locale: locale)),
        row(Copy.appearanceSize(bundle: bundle, locale: locale), Copy.appearanceSizeDetail(bundle: bundle, locale: locale)),
        row(Copy.appearanceLineHeight(bundle: bundle, locale: locale), Copy.appearanceLineHeightDetail(bundle: bundle, locale: locale)),
        row(Copy.appearanceLigatures(bundle: bundle, locale: locale), Copy.appearanceLigaturesDetail(bundle: bundle, locale: locale)),
        row(Copy.appearanceWrap(bundle: bundle, locale: locale), Copy.appearanceWrapDetail(bundle: bundle, locale: locale)),
        row(Copy.appearanceLineNumbers(bundle: bundle, locale: locale), Copy.appearanceLineNumbersDetail(bundle: bundle, locale: locale)))
    return AppearancePage(
        theme: groups.0, look: groups.1, color: groups.2, code: groups.3,
        colorScheme: look.0, textSize: look.1, textSizeValue: Copy.appearanceTextSizeValue(size: textSize, bundle: bundle, locale: locale),
        iconSet: look.2, iconWeight: look.3, iconWeightValue: weight, density: look.4, byShape: look.5,
        stateWorking: Copy.appearanceStateWorking(bundle: bundle, locale: locale), stateNeedsAttention: Copy.appearanceStateNeedsAttention(bundle: bundle, locale: locale),
        stateReady: Copy.appearanceStateReady(bundle: bundle, locale: locale), stateProblem: Copy.appearanceStateProblem(bundle: bundle, locale: locale),
        accent: color.0, tint: color.1, translucent: color.2,
        font: code.0, size: code.1, codeSize: Copy.appearanceCodeSize(bundle: bundle, locale: locale),
        codeSizeValue: Copy.appearanceCodeSizeValue(size: codeSize, bundle: bundle, locale: locale),
        lineHeight: code.2, ligatures: code.3, wrap: code.4, lineNumbers: code.5)
}
