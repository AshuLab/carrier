import Foundation

// The processes card (docs/specs/background-processes-apart-from-the-turn.md): what the window's Processes button and its list say of the
// background processes of a session. It is decided here from the session's tasks and whether the host can stop one; the views only draw it.

/// What the list says: the count, the Stop of its foot (nil when the host cannot stop a process by itself), and the processes, one row each.
public struct ProcessesCard: Equatable {
    public let processes: [BackgroundTask]
    /// "2 processes still running" ("1 process still running").
    public let title: String
    /// The foot's Stop: "Stop all" with more than one process, "Stop" with one; nil when the host does not list `stopTask`, and then the list has no Stop at all.
    public let stop: String?
    /// What the Stop of the foot says on hover and to VoiceOver.
    public let stopHelp: String?
    /// Whether each row has its own Stop.
    public var stopsEach: Bool { stop != nil }

    init(processes: [BackgroundTask], title: String, stop: String?, stopHelp: String?) {
        (self.processes, self.title, self.stop, self.stopHelp) = (processes, title, stop, stopHelp)
    }
}

extension ProcessesCard {
    /// The card for the processes among `tasks` (agent work is the cyan card's); nil when there is none: the button is gone with the last process.
    public init?(_ tasks: [BackgroundTask], canStop: Bool, bundle: Bundle? = nil, locale: Locale = .current) {
        let processes = tasks.filter { $0.agentWork == false }
        guard processes.isEmpty == false else { return nil }
        self.init(
            processes: processes,
            title: Copy.chatProcessesTitle(count: processes.count, bundle: bundle, locale: locale),
            stop: canStop ? (processes.count > 1 ? Copy.chatStopAll(bundle: bundle, locale: locale) : Copy.chatStop(bundle: bundle, locale: locale)) : nil,
            stopHelp: canStop ? Copy.chatProcessesStopHelp(count: processes.count, bundle: bundle, locale: locale) : nil
        )
    }
}
