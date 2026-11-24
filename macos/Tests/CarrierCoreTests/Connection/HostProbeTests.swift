import Foundation
import Testing
@testable import CarrierCore

// What the Health tab reads off the machine: the chat host's socket and hello, and the installed `carrier`'s version.

private struct FakeSocket: HostSocket {
    let hello: HostHello
    func answers(at path: String) -> Bool { hello != .nobody }
    func hello(at path: String) -> HostHello { hello }
}

private let command = StartCommand(
    program: "/opt/carrier", arguments: ["--flag", "chat-host"], environment: ["PATH": "/p"], processDir: "/d", logPath: "/d/l", socketPath: "/d/chat.sock")

private func probe(_ hello: HostHello, version: Result<ProcessResult, Error> = .success(ProcessResult(output: "1.4.0\n", status: 0))) -> (HostProbe, FakeProcessRunner) {
    let runner = FakeProcessRunner(runs: [version])
    return (HostProbe(runner: runner, socket: FakeSocket(hello: hello)), runner)
}

@Test func noAnswerFromTheSocketIsAHostThatIsNotRunning() async {
    let (probe, _) = probe(.nobody)
    let facts = await probe.read(command)
    #expect(facts.hostRunning == false && facts.hostVersion == nil && facts.installedVersion == "1.4.0")
}

@Test func aHelloWithoutHealthIsAHostThatDoesNotReportIt() async {
    let hello = ControlClient.Hello(protocolVersion: 1, version: "1.3.0", capabilities: [.sessions])
    let facts = await probe(.said(hello)).0.read(command)
    #expect(facts.hostRunning && facts.hostVersion == "1.3.0" && facts.hostReportsHealth == false)
}

@Test func aHelloWithHealthIsAHostThatReportsIt() async {
    let hello = ControlClient.Hello(protocolVersion: 1, version: "1.4.0", capabilities: [.health])
    let facts = await probe(.said(hello)).0.read(command)
    #expect(facts.hostRunning && facts.hostReportsHealth)
}

@Test func aHostThatAnswersButWhoseHelloCannotBeReadIsRunningAndReportsHealthByDefault() async {
    let facts = await probe(.unreadable).0.read(command)
    #expect(facts.hostRunning && facts.hostVersion == nil && facts.hostReportsHealth)
}

@Test func withoutACommandThereIsNoInstalledVersionAndNothingIsRun() async {
    let (probe, runner) = probe(.nobody)
    #expect(await probe.read(nil).installedVersion == nil && runner.ran.isEmpty)
}

@Test func theInstalledVersionIsAskedWithoutTheHostsSubcommandAndTrimmed() async {
    let (probe, runner) = probe(.nobody)
    #expect(await probe.installedVersion(command) == "1.4.0")
    #expect(runner.ran == [ProcessCommand(program: "/opt/carrier", arguments: ["--flag", "--version"], environment: ["PATH": "/p"])])
}

@Test func aVersionThatCannotBeReadIsNil() async {
    struct Refused: Error {}
    for result: Result<ProcessResult, Error> in [
        .success(ProcessResult(output: "1.4.0", status: 1)), .success(ProcessResult(output: "", status: 15, timedOut: true)),
        .success(ProcessResult(output: "unknown\n", status: 0)), .failure(Refused()),
    ] {
        #expect(await probe(.nobody, version: result).0.installedVersion(command) == nil)
    }
}
