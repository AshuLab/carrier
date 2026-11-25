import Foundation
import Testing

/// A view takes its size from the type scale (`scaledFont`, `TypeScale.font`, `NSFont.scaled`, `NSFont.scaledMono`); only the file that holds those helpers builds a font from a number.
@Suite struct NoHandSetFontSize {
    private static let helpers = "ScaledFont.swift"
    private static let byHand = try! NSRegularExpression(pattern: #"\.system\(size:|SystemFont\(ofSize:|NSFont\(name:|\.custom\("#)

    // The files of the app (fewer than `minimum` fails), and the line of every font set by hand outside the helpers.
    static func offenders(in sources: URL, minimum: Int) throws -> [String] {
        var found: [String] = []
        for file in try swiftFiles(under: sources, minimum: minimum).sorted(by: { $0.path < $1.path }) where file.lastPathComponent != helpers {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            for (index, line) in lines.enumerated() where byHand.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                found.append("\(file.lastPathComponent):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        return found
    }

    @Test func noViewSetsAFontSizeByHand() throws {
        let sources = testPaths().sources
        let found = try Self.offenders(in: sources, minimum: 100)
        #expect(found.isEmpty, "Set by hand, take the size from the type scale (.scaledFont):\n\(found.joined(separator: "\n"))")
    }

    @Test func theScanFindsAFontSetByHand() throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        try "Text(\"a\")\n    .font(.system(size: 12))\n".write(to: scratch.appendingPathComponent("View.swift"), atomically: true, encoding: .utf8)
        #expect(try Self.offenders(in: scratch, minimum: 1) == ["View.swift:2: .font(.system(size: 12))"])
    }

    @Test func scanningAnEmptyFolderFails() throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        #expect(throws: TooFewFiles.self) { try Self.offenders(in: scratch, minimum: 100) }
    }
}
