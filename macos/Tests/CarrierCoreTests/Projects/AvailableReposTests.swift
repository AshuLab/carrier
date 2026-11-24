import Foundation
import Testing
@testable import CarrierCore

private let now = ISO8601DateFormatter().date(from: "2026-10-22T12:00:00Z")!

@Test func theSecondsSincePushAreSaidInTheLargestUnit() {
    func line(_ iso: String) -> String { pushedLine(iso, now: now) }
    #expect(line("2026-10-22T11:59:30Z") == "pushed just now" && line("2026-10-22T09:00:00Z") == "pushed 3 h ago")
    #expect(line("2026-10-21T10:00:00Z") == "pushed yesterday" && line("2026-10-01T12:00:00Z") == "pushed 3 w ago")
    #expect(line("2026-05-01T12:00:00Z") == "pushed 5 mo ago" && pushedLine(nil, now: now) == "" && pushedLine("yesterday-ish", now: now) == "")
    #expect(line("2025-10-22T12:00:00Z") == "pushed 1 y ago" && line("2025-08-22T12:00:00Z") == "pushed 1 y 2 mo ago")
    #expect(line("2020-07-22T12:00:00Z") == "pushed 6 y 3 mo ago")
}
