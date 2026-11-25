import Foundation
import Testing
@testable import CarrierCore

private let printed = "Fetching available models...\ngemini-4-argon-low\tGemini 4 Argon (Low)\nnot a model\ngemini-4-argon-high\tGemini 4 Argon (High)\n"

@Test func agyModelsAreAskedOfTheBinaryWithTwentySecondsAndParsed() async {
    let runner = FakeProcessRunner(runs: [.success(ProcessResult(output: printed, status: 0))])
    let models = await AgyModels(runner: runner).load(binary: "/opt/agy", environment: ["HOME": "/h"])
    #expect(models.map(\.id) == ["gemini-4-argon-low", "gemini-4-argon-high"])
    #expect(runner.ran == [ProcessCommand(program: "/opt/agy", arguments: ["models"], environment: ["HOME": "/h"], limit: 20)])
}

@Test func agyModelsAreNothingWhenTheProcessFailsTimesOutCannotStartOrPrintsNothing() async {
    struct Refused: Error {}
    for result: Result<ProcessResult, Error> in [
        .success(ProcessResult(output: printed, status: 1)), .success(ProcessResult(output: printed, status: 0, timedOut: true)),
        .success(ProcessResult(output: "", status: 0)), .success(ProcessResult(output: "Fetching available models...\n", status: 0)), .failure(Refused()),
    ] {
        #expect(await AgyModels(runner: FakeProcessRunner(runs: [result])).load(binary: "/opt/agy", environment: [:]).isEmpty)
    }
}
