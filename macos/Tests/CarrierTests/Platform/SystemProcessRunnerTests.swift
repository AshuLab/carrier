import CarrierCore
import Foundation
import Testing
@testable import Carrier

@Test func theSystemRunnerGivesAProgramItsStandardInputAndGetsBackItsOutputAndStatus() async throws {
    let runner: any ProcessRunner = SystemProcessRunner()
    let echoed = try await runner.run(ProcessCommand(program: "/bin/cat", input: Data("one line\n".utf8)))
    #expect(echoed == ProcessResult(output: "one line\n", status: 0))
    let failed = try await runner.run(ProcessCommand(program: "/bin/sh", arguments: ["-c", "read line; echo \"$line $CARRIER_TEST\"; exit 3"], environment: ["CARRIER_TEST": "env"], input: Data("hi\n".utf8)))
    #expect(failed.output == "hi env\n" && failed.status == 3 && failed.timedOut == false)
    await #expect(throws: (any Error).self) { _ = try await runner.run(ProcessCommand(program: "/nonexistent/carrier")) }
}

@Test func theSystemRunnerEndsAProgramThatTakesLongerThanItsLimit() async throws {
    let result = try await SystemProcessRunner().run(ProcessCommand(program: "/bin/sleep", arguments: ["30"], limit: 0.2))
    #expect(result.timedOut)
}

@Test func theCoreDoesNotNameTheRunnerThatImplementsTheProtocol() throws {
    let core = testPaths().sources.appendingPathComponent("CarrierCore")
    let enumerator = try #require(FileManager.default.enumerator(at: core, includingPropertiesForKeys: nil))
    for case let file as URL in enumerator where file.pathExtension == "swift" {
        #expect(try String(contentsOf: file, encoding: .utf8).contains("SystemProcessRunner") == false, Comment(rawValue: file.lastPathComponent))
    }
}
