import Foundation
import Testing
@testable import CarrierCore

private func object(_ data: Data?) throws -> [String: Any] {
    let data = try #require(data)
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

@Test func theAgesAreTheFilesAndTheDefaultsWhenItHasNoneOrHasAWrongOne() {
    func ages(_ json: String?) -> SessionAges { sessionAges(chatJSON: json.map { Data($0.utf8) }) }
    #expect(ages(nil) == SessionAges(archive: .days(15), delete: .days(30)))
    #expect(ages("{}") == SessionAges())
    #expect(ages(#"{"archiveAfterDays":7,"deleteAfterDays":"never"}"#) == SessionAges(archive: .days(7), delete: .never))
    #expect(ages(#"{"archiveAfterDays":"never"}"#) == SessionAges(archive: .never, delete: .days(30)))
    for wrong in [#"0"#, #"-1"#, #"1.5"#, #""15""#, "null"] { #expect(ages(#"{"archiveAfterDays":\#(wrong)}"#) == SessionAges(), Comment(rawValue: wrong)) }
    #expect(ages("nope") == SessionAges() && ages("[1]") == SessionAges())
}

@Test func changingTheAgesKeepsTheOtherKeysAndLeavesDefaultsOut() throws {
    let file = Data(#"{"agents":{"a":{"harness":"claude"}},"logLevel":"debug","archiveAfterDays":5,"deleteAfterDays":9}"#.utf8)
    let changed = try object(applyingSessionAges(SessionAges(archive: .days(7), delete: .days(30)), to: file))
    #expect(changed["archiveAfterDays"] as? Int == 7 && changed["deleteAfterDays"] == nil)
    #expect(changed["agents"] != nil && changed["logLevel"] as? String == "debug")
    let defaults = try object(applyingSessionAges(SessionAges(), to: file))
    #expect(defaults["archiveAfterDays"] == nil && defaults["deleteAfterDays"] == nil && defaults["logLevel"] as? String == "debug")
    let never = try object(applyingSessionAges(SessionAges(archive: .never, delete: .days(40)), to: nil))
    #expect(never as NSDictionary == ["archiveAfterDays": "never", "deleteAfterDays": 40])
    #expect(try object(applyingSessionAges(SessionAges(archive: .days(3), delete: .never), to: nil)) as NSDictionary == ["archiveAfterDays": 3, "deleteAfterDays": "never"])
    #expect(try object(applyingSessionAges(SessionAges(), to: nil)).isEmpty)
}

@Test func theResetWritesTheDefaultsBackAndTheFileReadsThem() throws {
    let file = Data(#"{"logLevel":"debug","archiveAfterDays":"never","deleteAfterDays":9}"#.utf8)
    let written = try #require(applyingSessionAges(SessionAges(), to: file))
    #expect(sessionAges(chatJSON: written) == SessionAges(archive: .days(15), delete: .days(30)))
    #expect(try object(written)["logLevel"] as? String == "debug")
}

@Test func theAgesAreNotWrittenOverAFileThatCannotBeReadOrWhenTheyBreakTheRule() {
    #expect(applyingSessionAges(SessionAges(), to: Data("[1]".utf8)) == nil && applyingSessionAges(SessionAges(), to: Data("nope".utf8)) == nil)
    #expect(applyingSessionAges(SessionAges(archive: .days(30), delete: .days(30)), to: nil) == nil)
    #expect(applyingSessionAges(SessionAges(archive: .days(15), delete: .days(10)), to: nil) == nil)
    #expect(applyingSessionAges(SessionAges(archive: .days(0), delete: .days(30)), to: nil) == nil)
}

@Test func theFieldsSayWhyAValueIsRefusedAndNeverOnEitherSideHasNoComparison() {
    func problems(_ archive: SessionAge, _ delete: SessionAge) -> [SessionAgeField: String] { sessionAgeProblems(SessionAges(archive: archive, delete: delete)) }
    #expect(problems(.days(15), .days(30)).isEmpty && problems(.days(15), .never).isEmpty && problems(.never, .days(5)).isEmpty && problems(.never, .never).isEmpty)
    #expect(problems(.days(30), .days(30))[.delete]?.contains("greater than the archive age (30 days)") == true)
    #expect(problems(.days(15), .days(10))[.delete] != nil && problems(.days(15), .days(10))[.archive] == nil)
    #expect(problems(.days(0), .days(30))[.archive] != nil && problems(.days(15), .days(-1))[.delete] != nil)
}

@Test func deleteIsOffWithTheReasonWhileArchiveIsNever() {
    #expect(deleteAgeOffReason(SessionAges(archive: .never, delete: .days(30)))?.contains("archive is Never") == true)
    #expect(deleteAgeOffReason(SessionAges(archive: .days(15), delete: .never)) == nil && deleteAgeOffReason(SessionAges()) == nil)
}

@Test func aHalfTypedDeleteFieldDoesNotBlockSavingWhileItIsOffButDoesWhenItIsOn() {
    let off = SessionAges(archive: .never, delete: .days(30))
    #expect(sessionAgeProblems(off, unparsable: [.delete]).isEmpty)
    #expect(sessionAgeProblems(off, unparsable: [.archive])[.archive] == "Must be a number")
    #expect(sessionAgeProblems(SessionAges(), unparsable: [.delete])[.delete] == "Must be a number")
}

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func line(_ ages: SessionAges, on year: Int, _ month: Int, _ day: Int, unparsable: Set<SessionAgeField> = []) -> String? {
    let today = utc.date(from: DateComponents(year: year, month: month, day: day, hour: 23, minute: 30))!
    return sessionAgesLine(ages, today: today, calendar: utc, unparsable: unparsable)
}

@Test func theLineSaysWhenASessionLeftAloneFromTodayIsArchivedAndDeleted() {
    #expect(line(SessionAges(), on: 2026, 11, 13) == "Is archived on Nov 28 and deleted on Dec 13. Both ages count from its last activity")
    #expect(line(SessionAges(archive: .days(7), delete: .days(10)), on: 2026, 11, 13) == "Is archived on Nov 20 and deleted on Nov 23. Both ages count from its last activity")
}

@Test func theLineForNeverSaysNothingGoesOrThatItIsNeverDeleted() {
    #expect(line(SessionAges(archive: .never, delete: .days(30)), on: 2026, 11, 13) == "Is never archived or deleted")
    #expect(line(SessionAges(archive: .never, delete: .never), on: 2026, 11, 13) == "Is never archived or deleted")
    #expect(line(SessionAges(archive: .days(15), delete: .never), on: 2026, 11, 13) == "Is archived on Nov 28 and never deleted. The age counts from its last activity")
}

@Test func theLineIsNotShownWhileAnAgeIsRefused() {
    #expect(line(SessionAges(archive: .days(30), delete: .days(30)), on: 2026, 11, 13) == nil)
    #expect(line(SessionAges(archive: .days(0), delete: .days(30)), on: 2026, 11, 13) == nil)
    #expect(line(SessionAges(), on: 2026, 11, 13, unparsable: [.archive]) == nil)
}

@Test func theYearIsWrittenOnlyForADateThatIsNotInThisYear() {
    #expect(line(SessionAges(), on: 2026, 12, 20) == "Is archived on Jan 4, 2027 and deleted on Jan 19, 2027. Both ages count from its last activity")
    #expect(line(SessionAges(), on: 2026, 12, 1) == "Is archived on Dec 16 and deleted on Dec 31. Both ages count from its last activity")
    #expect(line(SessionAges(archive: .days(15), delete: .days(45)), on: 2026, 12, 1) == "Is archived on Dec 16 and deleted on Jan 15, 2027. Both ages count from its last activity")
}

@Test func theDatesCrossTheEndOfAMonthAndALeapDay() {
    #expect(line(SessionAges(archive: .days(3), delete: .days(10)), on: 2026, 1, 30) == "Is archived on Feb 2 and deleted on Feb 9. Both ages count from its last activity")
    #expect(line(SessionAges(archive: .days(1), delete: .days(2)), on: 2028, 2, 28) == "Is archived on Feb 29 and deleted on Mar 1. Both ages count from its last activity")
    #expect(line(SessionAges(archive: .days(1), delete: .days(2)), on: 2026, 2, 28) == "Is archived on Mar 1 and deleted on Mar 2. Both ages count from its last activity")
}
