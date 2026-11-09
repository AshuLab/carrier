/// The four states a color can tell apart: an epic's, a session's and a call's. "Tell the states apart by shape" puts the symbol of
/// each beside its color, so that color is not the only clue.
public enum StateShape: CaseIterable {
    case working, needsAttention, ready, problem
}

/// The SF Symbol of a state, a different one for each.
public func stateSymbol(_ shape: StateShape) -> String {
    switch shape {
    case .working: "arrow.triangle.2.circlepath"
    case .needsAttention: "exclamationmark.triangle.fill"
    case .ready: "checkmark.seal.fill"
    case .problem: "xmark.octagon.fill"
    }
}

extension EpicMenuState {
    /// The epic's state as one of the four; the others (up next, done, cancelled) are not told apart by color alone.
    public func shape(attention: Attention? = nil) -> StateShape? {
        switch self {
        case .running: .working
        case .needsYou: attention == .error ? .problem : .needsAttention
        case .ready: .ready
        case .waiting, .done, .cancelled: nil
        }
    }
}

extension SessionState {
    public var shape: StateShape? {
        switch self {
        case .working: .working
        case .waiting: .needsAttention
        case .idle, .done: nil
        }
    }
}

extension StepState {
    public var shape: StateShape? {
        switch self {
        case .current: .working
        case .input: .needsAttention
        case .error: .problem
        case .done, .waiting, .cancelled: nil
        }
    }
}

extension CallStatus {
    public var shape: StateShape? {
        switch self {
        case .running: .working
        case .failed: .problem
        case .ok, .stopped: nil
        }
    }
}
