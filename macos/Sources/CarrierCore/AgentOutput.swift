import Foundation

/// What `OutputWatcher` needs of a connection; `ControlClient` is the real one.
public protocol TailClient {
    func tail(executionId: String, lines: Int) throws -> [String]
    func close()
}

extension ControlClient: TailClient {}

/// A connection to Carrier ready for `tail`; nil when Carrier is not there or speaks another protocol.
public func connectForTail(socketPath: String) -> TailClient? {
    guard let client = ControlClient.connect(path: socketPath) else { return nil }
    guard (try? client.hello()) == 1 else {
        client.close()
        return nil
    }
    return client
}

public enum OutputUpdate: Equatable {
    /// The latest lines; empty while the execution has written nothing.
    case lines([String])
    /// Carrier refused or did not answer this request; the next one is still made.
    case error(String)
    /// The connection is gone; nothing more is asked.
    case carrierStopped
}

/// Reads an execution's latest output while a view is open: the first request at once, then one every `interval`, on one
/// connection. `run()` blocks, so it belongs on its own thread; `onUpdate` is called from it, once per request. `wait` is how
/// it sleeps: it returns false when the view closed, which ends `run()` without another request.
public final class OutputWatcher {
    private let executionId: String
    private let count: Int
    private let interval: TimeInterval
    private let connect: () -> TailClient?
    private let wait: (TimeInterval) -> Bool
    private let onUpdate: (OutputUpdate) -> Void
    private let log: (String) -> Void

    public init(
        executionId: String,
        count: Int = 60,
        interval: TimeInterval = 2,
        connect: @escaping () -> TailClient?,
        wait: @escaping (TimeInterval) -> Bool = { Thread.sleep(forTimeInterval: $0); return true },
        log: @escaping (String) -> Void = { FileHandle.standardError.write(Data("carrier: \($0)\n".utf8)) },
        onUpdate: @escaping (OutputUpdate) -> Void
    ) {
        self.executionId = executionId
        self.count = count
        self.interval = interval
        self.connect = connect
        self.wait = wait
        self.log = log
        self.onUpdate = onUpdate
    }

    public func run() {
        guard let client = connect() else {
            onUpdate(.carrierStopped)
            return
        }
        defer { client.close() }
        repeat {
            do {
                onUpdate(.lines(try client.tail(executionId: executionId, lines: count)))
            } catch ControlError.remote(let text) {
                onUpdate(.error(text))
            } catch ControlError.timeout {
                onUpdate(.error("Carrier did not answer"))
            } catch ControlError.closed {
                onUpdate(.carrierStopped)
                return
            } catch {
                log("tail connection failed: \(error)")
                onUpdate(.carrierStopped)
                return
            }
        } while wait(interval)
    }
}
