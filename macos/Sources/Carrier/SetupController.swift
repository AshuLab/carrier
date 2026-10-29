import CarrierCore
import Foundation

/// The setup the app starts Carrier with: loaded from user defaults, filled by asking the shell when nothing is saved,
/// and again only when the person asks. Saved on every edit.
final class SetupController: ObservableObject {
    static let shared = SetupController()

    private let store: SetupStore
    /// asks the shell; replaced in tests
    private let detector: () -> Detection?
    /// nothing saved yet: the first launch
    private let isFirstLaunch: Bool
    /// how many times this process started the shell; the self-test shows it stays 0 when values were saved
    private(set) var detectionRuns = 0

    @Published var settings: SetupSettings { didSet { store.save(settings) } }
    @Published private(set) var detecting = false
    @Published private(set) var message: String?

    private convenience init() { self.init(store: SetupStore(), detector: ShellDetector.run) }

    init(store: SetupStore, detector: @escaping () -> Detection?) {
        self.store = store
        self.detector = detector
        let saved = store.load()
        isFirstLaunch = saved == nil
        // the config path is not the shell's to say: it comes from where Carrier keeps it
        settings = saved ?? SetupSettings(detection: nil, environment: ProcessInfo.processInfo.environment, home: NSHomeDirectory())
    }

    /// Asks the shell only when nothing was saved. `done` runs once the settings are known: at once, or when the shell answered.
    func detectIfFirstLaunch(then done: @escaping () -> Void) {
        if isFirstLaunch { detect(then: done) } else { done() }
    }

    /// Runs the shell off the main thread and puts what it found in the three values it can find. Edits to the config path
    /// stay; a shell that gave no answer leaves every value as it was.
    func detect(then done: (() -> Void)? = nil) {
        guard detecting == false else { return }
        detecting = true
        message = nil
        detectionRuns += 1
        DispatchQueue.global(qos: .userInitiated).async {
            let detection = self.detector()
            DispatchQueue.main.async {
                if let detection {
                    self.settings.carrier = detection.carrier ?? ""
                    self.settings.node = detection.node ?? ""
                    self.settings.path = detection.path ?? ""
                } else {
                    self.message = "The shell gave no answer within \(Int(ShellDetector.limit)) seconds. Edit the values or try again."
                    self.store.save(self.settings)
                }
                self.detecting = false
                done?()
            }
        }
    }

    /// For the self-test.
    var summary: String {
        "saved \(store.load() != nil), shell runs this launch \(detectionRuns), not found [\(settings.missing.joined(separator: ", "))]"
    }
}
