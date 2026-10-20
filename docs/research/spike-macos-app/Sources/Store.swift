import SwiftUI
import Combine

enum Stage: String { case ship, review, fix }

struct FakeEpic: Identifiable {
    let id = UUID()
    var repo: String
    var issue: Int
    var title: String
    var needsHuman = false
    var stage: Stage?
    var round: Int?
    var blockers = 0
    var stageMinutes: Int
    var activitySeconds: Int
    var slicesDone: Int
    var slicesTotal: Int
    var pr: Int?
    var now: String
    var reason: String?
}

enum Scenario: String, CaseIterable, Identifiable {
    case stopped, idle, working, attention
    var id: String { rawValue }
}

final class Store: ObservableObject {
    static let shared = Store()
    static let ca = ProcessInfo.processInfo.environment["SPIKE_CA"] == "1"
    var openWindowHook: (() -> Void)?
    static let appkit = ProcessInfo.processInfo.environment["SPIKE_APPKIT"] == "1"
    /// seconds per animation frame; env SPIKE_FRAME overrides it so the cost can be measured
    static let frame: Double = Double(ProcessInfo.processInfo.environment["SPIKE_FRAME"] ?? "") ?? 0.08
    @Published var scenario: Scenario = Scenario(rawValue: ProcessInfo.processInfo.environment["SPIKE_SCENARIO"] ?? "") ?? .working
    @Published var variant: IconVariant = .bar
    @Published var motion: IconMotion = .sweep
    @Published var phase: Double = 0
    @Published var tick = 0
    private var animator: AnyCancellable?
    private var timer: AnyCancellable?

    init() {
        // Menu bar animation: redraw the icon at ~12 fps, only while epics are running.
        animator = Timer.publish(every: Store.frame, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self, !Store.appkit, !Store.ca, self.motion != .none, !self.running.isEmpty else { return }
            self.phase = (self.phase + Store.frame / 1.2).truncatingRemainder(dividingBy: 1)
        }
        timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.tick += 1 }
    }

    var running: [FakeEpic] {
        guard scenario == .working || scenario == .attention else { return [] }
        let a = 4 + tick % 6           // slices closed, loops 4...9 so the progress visibly moves
        return [
            FakeEpic(repo: "acme/web", issue: 42, title: "Checkout redesign", stage: .review, round: 2, blockers: 1,
                     stageMinutes: 18, activitySeconds: 40, slicesDone: min(a, 9), slicesTotal: 9, pr: 131,
                     now: "reviewer: reading src/cart/summary.tsx"),
            FakeEpic(repo: "acme/api", issue: 118, title: "Rate limit per organization", stage: .ship, stageMinutes: 52, activitySeconds: 8,
                     slicesDone: 3 + tick % 3, slicesTotal: 7, now: "author: pnpm test (slice #121)"),
        ]
    }
    var needsYou: [FakeEpic] {
        scenario == .attention
            ? [FakeEpic(repo: "acme/web", issue: 51, title: "Dark mode tokens", needsHuman: true, stage: .fix, round: 5, blockers: 2,
                        stageMinutes: 190, activitySeconds: 3600, slicesDone: 5, slicesTotal: 6, pr: 127, now: "",
                        reason: "Review limit reached: 5 rounds, 2 blockers left")]
            : []
    }
    var queue: [String] { scenario == .idle || scenario == .stopped ? [] : ["acme/docs#7", "acme/api#120"] }
    var readyForTest: [(String, String)] {
        scenario == .stopped ? [] : [("acme/api#112", "PR #130 · 2 h ago"), ("acme/web#39", "PR #124 · yesterday")]
    }
    var iconState: IconState {
        let r = running
        return IconState(connected: scenario != .stopped, working: r.count,
                         done: r.reduce(0) { $0 + $1.slicesDone }, total: r.reduce(0) { $0 + $1.slicesTotal },
                         attention: needsYou.count)
    }
    static let baked = ProcessInfo.processInfo.environment["SPIKE_BAKED"] == "1"
    func menuImage() -> NSImage {
        Store.baked ? cachedIcon(variant, iconState, phase: phase, motion: motion)
                    : iconImage(variant, iconState, fg: nil, phase: phase, motion: motion)
    }
}
