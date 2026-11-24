import Foundation
import Testing
@testable import CarrierCore

/// What `/bin/sh` makes of the quoted value when it is the one argument of `printf '%s'`.
private func throughShell(_ value: String) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", "printf '%s' " + shellQuote(value)]
    let out = Pipe()
    process.standardOutput = out
    try process.run()
    let data = out.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
    return String(decoding: data, as: UTF8.self)
}

@Test(arguments: [
    "plain",
    "",
    "two words  and\ttab",
    "it's",
    "'''",
    "say \"hi\"",
    "$(touch /tmp/never)",
    "${HOME} $HOME `id` \\ ! * ? ; & | < > ( ) #",
    "line one\nline two\n",
    "-n",
    "--help",
    "-e \\n",
    "Jos\u{E9} \u{2603} \u{65E5}\u{672C}\u{8A9E} \u{1F680}",
    "~/folder with 'quotes' and \"double\" and $(x)",
])
func quotedValueComesBackUnchanged(value: String) throws {
    #expect(try throughShell(value) == value)
}

@Test func quotesAreWrappedInSingleQuotes() {
    #expect(shellQuote("a b") == "'a b'")
    #expect(shellQuote("it's") == "'it'\\''s'")
}
