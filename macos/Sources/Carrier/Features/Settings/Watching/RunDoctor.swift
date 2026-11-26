import CarrierCore
import Foundation

/// Asks the doctor for its checks, as Watching does when it opens and on Check again, and as Identities does when it opens: not awaited, the store ignores a run
/// while one is running and runs only with an `engine.json`, and what it answers is `AppHealth.doctor.state`.
@MainActor func runSettingsDoctor() {
    let setup = SetupController.shared, configExists = StartController.shared.configExists
    let settings = setup.settings
    // a fixture has no `carrier` to find: any path will do, the run answers with the golden output
    let carrier = setup.carrier ?? (CommandLine.arguments.contains("--fixture") ? "/fixture/carrier" : nil)
    Task { await AppHealth.doctor.check(settings: settings, carrier: carrier, environment: ProcessInfo.processInfo.environment, configExists: configExists) }
}
