import Foundation

public enum ConnectionState: Equatable {
    case stopped
    case incompatible
    case running(PanelSnapshot)

    /// The one line the menu shows.
    public var menuLine: String {
        switch self {
        case .stopped: return "Carrier is stopped"
        case .incompatible: return "Carrier is an incompatible version"
        case .running(let snapshot):
            let epics = snapshot.epics.count
            return "Carrier running · \(epics) \(epics == 1 ? "epic" : "epics") · \(snapshot.slots.busy)/\(snapshot.slots.total) slots"
        }
    }

    public enum MenuTone: Equatable { case stopped, running, attention }

    /// The menu's heading: a bold title, a quieter detail, and the colour of the dot beside them.
    public var menuStatus: (title: String, detail: String?, tone: MenuTone) {
        switch self {
        case .stopped: return ("Carrier is stopped", nil, .stopped)
        case .incompatible: return ("Carrier is an incompatible version", nil, .attention)
        case .running(let snapshot):
            let epics = snapshot.epics.count
            let detail = "\(epics) \(epics == 1 ? "epic" : "epics") · \(snapshot.slots.busy)/\(snapshot.slots.total) slots"
            let needsYou = snapshot.epics.contains { $0.status == .needsHuman }
            let attention = snapshot.paused || needsYou || snapshot.problem != nil
            return (snapshot.paused ? "Intake paused" : "Carrier running", detail, attention ? .attention : .running)
        }
    }
}

/// Keeps the state of Carrier current: asks for the snapshot every `pollInterval` while connected, tries to connect again
/// every `retryInterval` while not. `run()` blocks, so it belongs on its own thread; `onChange` is called from it, once per
/// poll or attempt. `tick` is called after each snapshot on the same connection (the epic view's requests go there). `wait` is how it sleeps: it returns false to end `run()`.
public final class ControlMonitor {
    private let socketPath: String
    private let pollInterval: TimeInterval
    private let retryInterval: TimeInterval
    private let wait: (TimeInterval) -> Bool
    private let onChange: (ConnectionState) -> Void
    private let log: (String) -> Void
    private let tick: (ControlClient) throws -> Void

    public init(
        socketPath: String,
        pollInterval: TimeInterval = 1,
        retryInterval: TimeInterval = 3,
        wait: @escaping (TimeInterval) -> Bool = { Thread.sleep(forTimeInterval: $0); return true },
        log: @escaping (String) -> Void = { FileHandle.standardError.write(Data("carrier: \($0)\n".utf8)) },
        tick: @escaping (ControlClient) throws -> Void = { _ in },
        onChange: @escaping (ConnectionState) -> Void
    ) {
        self.socketPath = socketPath
        self.pollInterval = pollInterval
        self.retryInterval = retryInterval
        self.wait = wait
        self.log = log
        self.tick = tick
        self.onChange = onChange
    }

    public func run() {
        repeat {
            guard let client = ControlClient.connect(path: socketPath) else {
                onChange(.stopped)
                continue
            }
            defer { client.close() }
            // false: `wait` said stop while connected
            if poll(client) == false { return }
        } while wait(retryInterval)
    }

    /// Polls until the connection ends; false when `wait` asked to stop.
    private func poll(_ client: ControlClient) -> Bool {
        do {
            guard try client.hello().protocolVersion == 1 else {
                onChange(.incompatible)
                return true
            }
            while true {
                onChange(.running(try decodeSnapshot(client.request("snapshot"))))
                try tick(client)
                if wait(pollInterval) == false { return false }
            }
        } catch let error as SnapshotError {
            log("snapshot does not match this app: \(error)")
            onChange(.incompatible)
        } catch ControlError.closed {
            onChange(.stopped)
        } catch {
            log("control connection failed: \(error)")
            onChange(.stopped)
        }
        return true
    }
}
