import Foundation
import Testing
@testable import CarrierCore

@Test func aSessionWithABoxInFrontIsTheOnlyPlaceTheBoxTakesTheDictation() {
    func front(_ selection: Selection, settings: Bool = false, carrier: Bool = true, box: Bool = true) -> DictationFront {
        dictationFront(carrierIsFront: carrier, settingsShown: settings, selection: selection, sessionHasBox: box)
    }
    #expect(front(.session(id: "s1")) == .session)
    #expect(front(.epic(repo: "acme/web", issue: 7)) == .epic)
    #expect(front(.session(id: "s1"), settings: true) == .settings)
    #expect(front(.epic(repo: "acme/web", issue: 7), settings: true) == .settings)
    #expect(front(.session(id: "s1"), carrier: false) == .otherApp)
    #expect(front(.session(id: "s1"), settings: true, carrier: false) == .otherApp)
    // no box to dictate into: an archived session
    #expect(front(.session(id: "s1"), box: false) == .otherView)
    for other in [Selection.home, .sessions, .newSession, .terminals, .terminal(id: UUID()), .archive, .carrier, .usage] { #expect(front(other) == .otherView) }
}

@Test func theBoxIsRoutedOnlyForASessionAndTheWidgetEverywhereElse() {
    #expect(dictationRoute(for: .session) == .messageBox)
    for front in [DictationFront.epic, .settings, .otherView, .otherApp] { #expect(dictationRoute(for: front) == .widget) }
}
