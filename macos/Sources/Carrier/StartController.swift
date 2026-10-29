import AppKit
import CarrierCore
import Darwin
import SwiftUI

/// Starts Carrier detached and says why when it does not come up. A start is one at a time: pressing again while one is
/// under way does nothing. Pressed and answered on the main thread; the spawn and the wait run on a queue of their own.
final class StartController: ObservableObject {
    static let shared = StartController()

    @Published private(set) var starting = false

    var missing: [String] { startMissing(SetupController.shared.settings) }

    /// Whether the Carrier folder has its `config.json`; without it the engine does not start. Published so the views that read it
    /// follow the file while Carrier stays stopped: it is read again every 3 seconds and whenever `refreshConfig` is called.
    @Published private(set) var configExists = FileManager.default.fileExists(atPath: configFilePath())

    private init() {
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.refreshConfig() }
    }

    /// Reads the file again; the menu and the start call it so they never act on a value up to 3 seconds old.
    @discardableResult func refreshConfig() -> Bool {
        let exists = FileManager.default.fileExists(atPath: configFilePath())
        if exists != configExists { configExists = exists }
        return exists
    }

    /// `done` is called on the main thread with whether Carrier came up (also false when nothing was started).
    func start(done: ((Bool) -> Void)? = nil) {
        guard starting == false, refreshConfig() else { done?(false); return }
        guard let command = startCommand(settings: SetupController.shared.settings, environment: ProcessInfo.processInfo.environment) else { done?(false); return }
        starting = true
        DispatchQueue.global().async {
            let failure = Self.launch(command)
            DispatchQueue.main.async {
                self.starting = false
                if let failure { Self.showAlert(reason: failure.reason, tail: failure.tail) }
                done?(failure == nil)
            }
        }
    }

    /// Stops the running Carrier, waits for its socket to go, starts it again. `done` is called on the main thread with whether
    /// it came up; a failed start shows its own alert. The Behavior tab asks the person before it calls this.
    func restart(done: @escaping (Bool) -> Void) {
        NotificationWatcher.app.expectStop()
        let path = controlSocketPath()
        DispatchQueue.global().async {
            do { try send(.stop, socketPath: path) } catch {
                FileHandle.standardError.write(Data("carrier: restart: stop failed: \(error)\n".utf8))
                DispatchQueue.main.async { done(false) }
                return
            }
            // ponytail: polls the socket for 15 s, no signal from the engine that it is gone
            let deadline = Date().addingTimeInterval(15)
            while ControlClient.connect(path: path) != nil, Date() < deadline { Thread.sleep(forTimeInterval: 0.25) }
            DispatchQueue.main.async { self.start(done: done) }
        }
    }

    /// For the self-test: what a press would do, without doing it (it would start the real Carrier).
    func selfTest(state: ConnectionState) -> String {
        let item = startMenuState(state: state, starting: starting, missing: missing, configExists: configExists)
        guard item.enabled, let command = startCommand(settings: SetupController.shared.settings, environment: [:]) else {
            return "start disabled: \(item.title)"
        }
        return "start enabled, would run \(command.node) \(command.arguments.joined(separator: " ")), log \(command.logPath)"
    }

    /// Spawns Carrier and waits for its socket; nil when it came up, else what to tell the person.
    static func launch(_ command: StartCommand, name: String = "Carrier") -> (reason: String, tail: String)? {
        let log = URL(fileURLWithPath: command.logPath)
        do {
            try prepareLogFolder(command)
            let pid = try spawn(command)
            let exit = ExitCode()
            // the app is the parent: the exit has to be collected, whenever it comes
            Thread.detachNewThread { exit.set(wait(for: pid)) }
            let began = Date()
            while true {
                let answered = ControlClient.connect(path: command.socketPath) != nil
                switch startOutcome(exitCode: exit.value, socketAnswered: answered, elapsed: Date().timeIntervalSince(began)) {
                case .running?: return nil
                case .failed(let failure)?: return (startFailureText(failure, name: name), tail(of: log))
                case nil: Thread.sleep(forTimeInterval: 0.25)
                }
            }
        } catch {
            FileHandle.standardError.write(Data("carrier: \(name) start failed: \(error)\n".utf8))
            return ("\(name) could not be started: \(error.localizedDescription)", tail(of: log))
        }
    }

    /// The orchestrator folder is for the user only, as the engine makes it; the logs folder is inside it.
    private static func prepareLogFolder(_ command: StartCommand) throws {
        let files = FileManager.default
        try files.createDirectory(atPath: command.processDir, withIntermediateDirectories: true)
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: command.processDir)
        try files.createDirectory(atPath: command.logsDir, withIntermediateDirectories: true)
    }

    /// Its own session (so it outlives the app and has no terminal), stdin from /dev/null, stdout and stderr to the log,
    /// nothing else inherited from the app.
    private static func spawn(_ command: StartCommand) throws -> pid_t {
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 1, command.logPath, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        posix_spawn_file_actions_adddup2(&actions, 1, 2)

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        var defaults = sigset_t()
        sigfillset(&defaults)
        var none = sigset_t()
        sigemptyset(&none)
        posix_spawnattr_setsigdefault(&attributes, &defaults)
        posix_spawnattr_setsigmask(&attributes, &none)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))

        let argv = ([command.node] + command.arguments).map { strdup($0) } + [nil]
        let envp = command.environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { (argv + envp).forEach { free($0) } }

        var pid: pid_t = 0
        let result = posix_spawn(&pid, command.node, &actions, &attributes, argv, envp)
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: result) ?? .EIO) }
        return pid
    }

    /// Blocks until the process ends; a signal counts as 128 plus its number, as a shell reports it.
    private static func wait(for pid: pid_t) -> Int32 {
        var status: Int32 = 0
        while waitpid(pid, &status, 0) < 0 {
            guard errno == EINTR else { return -1 }
        }
        let signal = status & 0x7f
        return signal == 0 ? (status >> 8) & 0xff : 128 + signal
    }

    /// The end of the log, from its last 16 KB.
    private static func tail(of log: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: log) else { return logTail(Data()) }
        defer { try? handle.close() }
        if let size = try? handle.seekToEnd(), size > 16_384 { try? handle.seek(toOffset: size - 16_384) } else { try? handle.seek(toOffset: 0) }
        return logTail((try? handle.readToEnd()) ?? Data())
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
            text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            text.string = tail
        }
        if tail.isEmpty == false { alert.accessoryView = scroll }
        // an accessory app is not frontmost, and its alert would open behind the other windows
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

/// Set by the thread that waits for the process, read by the one that watches for the socket.
private final class ExitCode {
    private let lock = NSLock()
    private var code: Int32?
    var value: Int32? { lock.lock(); defer { lock.unlock() }; return code }
    func set(_ code: Int32) { lock.lock(); self.code = code; lock.unlock() }
}

/// The window's Start Carrier button, shown while Carrier is stopped; disabled while there is no config or the settings lack something
/// (the stopped view says what).
struct StartCarrierButton: View {
    @ObservedObject private var start = StartController.shared
    @ObservedObject private var setup = SetupController.shared

    var body: some View {
        let missing = startMissing(setup.settings)
        VStack(spacing: 6) {
            HStack {
                Button { start.start() } label: { Label("Start Carrier", systemImage: "play.fill") }
                    .buttonStyle(PrimaryCapsuleButtonStyle(large: true))
                    .disabled(missing.isEmpty == false || start.configExists == false || start.starting)
                if start.starting {
                    ProgressView().controlSize(.small)
                    Text("Starting…").foregroundStyle(.secondary)
                }
            }
        }
    }
}
