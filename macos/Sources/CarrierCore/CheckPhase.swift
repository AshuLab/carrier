/// Where a "Check again" button is: resting, running, or showing how the last check ended. The button's words and mark follow it.
public enum CheckPhase: Equatable, Sendable {
    case idle, checking, done, failed

    /// How long the result stays before the button rests again.
    public static let resultSeconds = 3.0

    /// The phase after `checking` changed. A check that starts is running. One that ends shows how it ended only when the person asked for it
    /// (`asked`): a page that checks by itself when it opens ends back at rest, with nothing to claim.
    public func moving(checking: Bool, failed: Bool, asked: Bool) -> CheckPhase {
        if checking { return .checking }
        guard self == .checking else { return self }
        guard asked else { return .idle }
        return failed ? .failed : .done
    }

    /// A click does something at rest and after a failure (it tries again); while it runs or shows its result it does nothing.
    public var accepts: Bool { self == .idle || self == .failed }
}

extension DoctorState {
    /// The doctor gave no answer (it could not run, or refused the config): a check that failed, not one that found problems.
    public var failedToAnswer: Bool {
        switch self {
        case .unknown, .refused: true
        case .idle, .running, .checks: false
        }
    }
}
