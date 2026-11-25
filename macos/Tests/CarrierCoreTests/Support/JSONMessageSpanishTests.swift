import Foundation
import Testing

@testable import CarrierCore

// What `JSONMessage` says by itself (the "Slice" of a title, the "PR #" and "Pull request" of a link) through copy keys, in each language. The keys of the report and
// the words of its values are the agent's, and stay as they came.

private let report = """
{"slice": "#285", "outcome": "ready-to-merge", "branch": "feat/x", "pr": "https://github.com/AshuLab/carrier/pull/1289",
 "definitionOfDone": {"typecheck": true}, "note": "Small."}
"""

private func slice(_ text: String, _ language: (bundle: Bundle, locale: Locale)) -> SliceReport? {
    guard case .slice(let found)? = jsonMessage(text, bundle: language.bundle, locale: language.locale) else { return nil }
    return found
}

@Test func aSliceReportSaysItsTitleAndItsPullRequestInSpanish() {
    let found = slice(report, spanish)
    #expect(found?.title == "Slice #285")
    // the pull request's number is not grouped by the locale: 1289 and not 1.289
    #expect(found?.pull?.label == "PR #1289")
    #expect(found?.note == "Small." && found?.branch == "feat/x")
}

@Test func aSliceNumberedWithABareNumberSaysItsTitleThroughItsOwnKey() {
    let text = #"{slice: 351, outcome: "ready-to-merge", definitionOfDone: {a: true}}"#
    #expect(slice(text, spanish)?.title == "Slice #351")
    #expect(slice(text, english)?.title == "Slice #351")
}

@Test func aPullRequestAddressThatIsNotAPullSaysPullRequestInBothLanguages() {
    let text = ##"{"outcome": "ready", "slice": "#1", "pr": "https://github.com/AshuLab/carrier/issues/12", "definitionOfDone": {"a": true}}"##
    #expect(slice(text, spanish)?.pull?.label == "Pull request")
    #expect(slice(text, english)?.pull?.label == "Pull request")
    #expect(slice(report, english)?.pull?.label == "PR #1289")
    #expect(slice(report, english)?.title == "Slice #285")
}
