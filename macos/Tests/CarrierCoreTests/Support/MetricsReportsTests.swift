import Foundation
import Testing
@testable import CarrierCore

@Test func theMetricsFolderKeepsTheNewestThirtyReportsInTheOrderTheyCame() throws {
    let folder = URL(fileURLWithPath: NSTemporaryDirectory() + "carrier-metrics-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    for second in 0..<35 {
        try keepMetricsReport(Data("{\"n\":\(second)}".utf8), kind: "metrics", in: folder, at: start.addingTimeInterval(Double(second)))
    }
    let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    #expect(names.count == 30)
    #expect(names.first == "1800000005-0-metrics.json")
    #expect(names.last == "1800000034-0-metrics.json")
}

@Test func twoReportsOfTheSameSecondAreBothKept() throws {
    let folder = URL(fileURLWithPath: NSTemporaryDirectory() + "carrier-metrics-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    let moment = Date(timeIntervalSince1970: 1_800_000_000)
    try keepMetricsReport(Data("{}".utf8), kind: "diagnostics", index: 0, in: folder, at: moment)
    try keepMetricsReport(Data("{}".utf8), kind: "diagnostics", index: 1, in: folder, at: moment)
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 2)
}

@Test func theMetricsFolderIsInsideTheAppLogs() {
    #expect(CarrierPlaces(folder: "/tmp/x").appMetrics == "/tmp/x/app/logs/metrics")
}
