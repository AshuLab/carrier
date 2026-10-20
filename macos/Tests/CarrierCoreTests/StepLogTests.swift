import Foundation
import Testing
@testable import CarrierCore

@Test func appendWritesOneLinePerStepInOrder() throws {
    let path = NSTemporaryDirectory() + "carrier-steplog-\(UUID().uuidString).log"
    defer { try? FileManager.default.removeItem(atPath: path) }

    let log = StepLog(path: path)
    try log.append("first")
    try log.append("second")

    let lines = try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n")
    #expect(lines.count == 2)
    #expect(lines[0].hasSuffix(" first"))
    #expect(lines[1].hasSuffix(" second"))
}
