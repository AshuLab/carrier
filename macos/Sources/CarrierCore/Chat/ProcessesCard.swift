import Foundation

// The processes card (docs/specs/background-processes-apart-from-the-turn.md): the grey card over the message box for the background
// processes of a session. What it says is decided here from the session's tasks and whether the host can stop one; the view only draws it.

/// What the grey card says: the count, the names on one line, the Stop of its line (nil when the host cannot stop a process by itself), and
/// the processes, one row each in the opened card.
public struct ProcessesCard: Equatable {
    public let processes: [BackgroundTask]
    /// "2 processes still running" ("1 process still running").
    public let title: String
    /// What each is called (what the agent said it was, else its kind), on one line.
    public let names: String
    /// The line's Stop: "Stop all" with more than one process, "Stop" with one; nil when the host does not list `stopTask`, and then the card has no Stop at all.
    public let stop: String?
    /// What the Stop of the line says on hover and to VoiceOver.
    public let stopHelp: String?
    /// Whether each row has its own Stop.
    public var stopsEach: Bool { stop != nil }

    init(processes: [BackgroundTask], title: String, names: String, stop: String?, stopHelp: String?) {
        (self.processes, self.title, self.names, self.stop, self.stopHelp) = (processes, title, names, stop, stopHelp)
    }
}

extension ProcessesCard {
    /// The card for the processes among `tasks` (agent work is the cyan card's); nil when there is none: the card is gone with the last process.
    public init?(_ tasks: [BackgroundTask], canStop: Bool, bundle: Bundle? = nil, locale: Locale = .current) {
        let processes = tasks.filter { $0.agentWork == false }
        guard processes.isEmpty == false else { return nil }
        self.init(
            processes: processes,
            title: Copy.chatProcessesTitle(count: processes.count, bundle: bundle, locale: locale),
            names: processes.map(\.name).joined(separator: ", "),
            stop: canStop ? (processes.count > 1 ? Copy.chatStopAll(bundle: bundle, locale: locale) : Copy.chatStop(bundle: bundle, locale: locale)) : nil,
            stopHelp: canStop ? Copy.chatProcessesStopHelp(count: processes.count, bundle: bundle, locale: locale) : nil
        )
    }
}
