import Foundation

/// Antigravity's models, read from its own CLI: the chat host has no adapter for it, so `agy models` is asked.
public struct AgyModels {
    let runner: any ProcessRunner

    public init(runner: any ProcessRunner) { self.runner = runner }

    /// The models `binary models` prints (see `parseAgyModels`); none when it cannot start, fails, runs out of its 20 seconds or prints no model.
    public func load(binary: String, environment: [String: String]) async -> [ModelOption] {
        guard let run = try? await runner.run(ProcessCommand(program: binary, arguments: ["models"], environment: environment, limit: 20)),
              run.status == 0, run.timedOut == false else { return [] }
        return parseAgyModels(run.output)
    }
}
