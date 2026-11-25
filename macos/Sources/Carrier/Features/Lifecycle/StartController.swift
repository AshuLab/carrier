import AppKit
import CarrierCore
import SwiftUI

/// Starts Carrier detached and says why when it does not come up. A start is one at a time (`CarrierStart`): pressing again while one is
/// under way does nothing. Pressed and answered on the main thread; the spawn and the wait run off it.
final class StartController: ObservableObject {
    static let shared = StartController()

    /// The code that starts Carrier and the chat host, on the app's own runner and socket.
    static let launcher = CarrierLauncher(runner: SystemProcessRunner(), socket: ControlSocket())
    private let core = CarrierStart(launcher: StartController.launcher)

    @Published private(set) var starting = false

    var missing: [String] { SetupController.shared.missing }

    /// Whether the Carrier folder has its `engine.json`; without it the engine does not start. Published so the views that read it
    /// follow the file while Carrier stays stopped: it is read again every 3 seconds and whenever `refreshConfig` is called.
    @Published private(set) var configExists = false

    private init() {
        configExists = core.configExists()
        core.onStartingChange = { [weak self] starting in DispatchQueue.main.async { self?.starting = starting } }
        let timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.refreshConfig() }
        // a setting on disk, not a deadline: the system may fold this wake-up into others
        timer.tolerance = 1
    }

    /// Reads the file again; the menu and the start call it so they never act on a value up to 3 seconds old.
    @discardableResult func refreshConfig() -> Bool {
        let exists = core.configExists()
        if exists != configExists { configExists = exists }
        return exists
    }

    /// `done` is called on the main thread with whether Carrier came up (also false when nothing was started).
    func start(done: ((Bool) -> Void)? = nil) {
        refreshConfig()
        let carrier = SetupController.shared.carrier, environment = ProcessInfo.processInfo.environment
        let command = startCommand(settings: SetupController.shared.settings, carrier: carrier, environment: environment)
        // a tool the PATH lacks: the shell is asked again and the start tried once more (`CarrierLauncher.launch`); the settings live on the main thread
        let retry = StartRetry(
            settings: { await MainActor.run { SetupController.shared.settings } },
            command: { startCommand(settings: $0, carrier: carrier, environment: environment) },
            save: { fresh in await MainActor.run { SetupController.shared.settings = fresh } }
        )
        Task {
            let result = await core.start(command, retry: retry)
            await MainActor.run {
                if case .failed(let failure) = result { Self.showAlert(reason: failure.reason, tail: failure.tail) }
                done?(result == .up)
            }
        }
    }

    /// For the self-test: what a press would do, without doing it (it would start the real Carrier).
    func selfTest(state: ConnectionState) -> String {
        let item = startMenuState(state: state, starting: starting, missing: missing, configExists: configExists)
        guard item.enabled, let command = startCommand(settings: SetupController.shared.settings, carrier: SetupController.shared.carrier, environment: [:]) else {
            return "start disabled: \(item.title)"
        }
        return "start enabled, would run \(command.program) \(command.arguments.joined(separator: " ")), log \(command.logPath)"
    }

    /// Alert with the reason and the end of the start log, readable and selectable.
    static func showAlert(title: String = "Carrier did not start", reason: String, tail: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = tail.isEmpty ? reason : reason + " The end of app-start.log:"
        let scroll = NSTextView.scrollableTextView()
        scroll.frame = NSRect(x: 0, y: 0, width: 520, height: 220)
        if let text = scroll.documentView as? NSTextView {
            text.isEditable = false
            text.font = NSFont.scaledMono(11)
            text.string = tail
        }
        if tail.isEmpty == false { alert.accessoryView = scroll }
        // an accessory app is not frontmost, and its alert would open behind the other windows
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

/// The window's Start Carrier button, shown while Carrier is stopped; disabled while there is no config or the settings lack something
/// (the stopped view says what).
struct StartCarrierButton: View {
    @Environment(\.pieceTheme) private var theme
    @ObservedObject private var start = StartController.shared
    @ObservedObject private var setup = SetupController.shared

    var body: some View {
        let missing = setup.missing
        VStack(spacing: Tokens.Space.s6) {
            HStack {
                let blocked = missing.isEmpty == false || start.configExists == false || start.starting
                Button { start.start() } label: {
                    Label("Start Carrier", icon: .playFilled).labelStyle(.titleAndIcon).scaledFont(14, weight: .semibold)
                        .foregroundStyle(blocked ? Color.secondary : .white)
                        .padding(.horizontal, Tokens.Space.s22).padding(.vertical, Tokens.Space.s10).contentShape(Capsule())
                }
                .buttonStyle(.plain)
                // the accent is a light pastel on the dark themes: darkened for the tint so the white label reads over any window behind it
                .glassEffect(blocked ? .regular : .regular.tint(theme.accent.mix(with: .black, by: 0.4)).interactive(), in: .capsule)
                .disabled(blocked)
                if start.starting {
                    ProgressView().controlSize(.small)
                    Text("Starting…").foregroundStyle(.secondary)
                }
            }
        }
    }
}
