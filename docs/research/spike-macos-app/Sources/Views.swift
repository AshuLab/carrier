import SwiftUI

func ago(minutes m: Int) -> String { m >= 60 ? "\(m / 60) h \(m % 60) min" : "\(m) min" }
func ago(seconds s: Int) -> String { s < 60 ? "\(s) s" : (s < 3600 ? "\(s / 60) min" : "\(s / 3600) h") }

struct Chip: View {
    let text: String; var on = false; var color: Color = .accentColor
    var body: some View {
        Text(text).font(.caption.weight(.medium)).padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(on ? color : Color.secondary.opacity(0.15)))
            .foregroundStyle(on ? Color.white : Color.secondary)
    }
}

struct EpicCard: View {
    let e: FakeEpic
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(e.repo)#\(e.issue)").font(.headline)
                Text(e.title).foregroundStyle(.secondary)
                Spacer()
                if e.needsHuman { Chip(text: "needs you", on: true, color: .orange) }
                if let pr = e.pr { Chip(text: "PR #\(pr)") }
            }
            HStack(spacing: 6) {
                ForEach([Stage.ship, .review, .fix], id: \.rawValue) { st in Chip(text: st.rawValue, on: e.stage == st) }
                if let r = e.round { Text("round \(r)/5").font(.caption).foregroundStyle(.secondary) }
                if e.blockers > 0 { Chip(text: "\(e.blockers) blocker\(e.blockers > 1 ? "s" : "")", on: true, color: .red) }
                Spacer()
                Text("in stage \(ago(minutes: e.stageMinutes)) · active \(ago(seconds: e.activitySeconds)) ago")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                ProgressView(value: Double(e.slicesDone), total: Double(max(e.slicesTotal, 1))).frame(maxWidth: 220)
                Text("\(e.slicesDone)/\(e.slicesTotal) slices").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if let r = e.reason { Text(r).font(.callout).foregroundStyle(.orange) }
            else if !e.now.isEmpty { Text(e.now).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1) }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
    }
}

struct PanelView: View {
    @ObservedObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                if store.scenario == .stopped {
                    Label("Carrier is stopped", systemImage: "stop.circle").font(.title3)
                    Spacer(); Button("Start Carrier") {}.buttonStyle(.borderedProminent)
                } else {
                    Label("Carrier running", systemImage: "play.circle.fill").foregroundStyle(.green).font(.title3)
                    Text("up 3 h 12 min · 2 repos · next check in 2 min").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Chip(text: "slots \(store.running.count)/3")
                    Button("Check now") {}; Button("Pause intake") {}; Button("Stop") {}
                }
            }
            if store.scenario == .stopped {
                Text("Nothing to show: the engine is not running.").foregroundStyle(.secondary)
            } else {
                if !store.needsYou.isEmpty { Section(title: "Needs you") { ForEach(store.needsYou) { EpicCard(e: $0) } } }
                if store.running.isEmpty { Text("Idle. Watching 2 repos for epics marked solve:epic:ready.").foregroundStyle(.secondary) }
                else { Section(title: "Running") { ForEach(store.running) { EpicCard(e: $0) } } }
                if !store.queue.isEmpty { Section(title: "Queue") { Text(store.queue.joined(separator: "  ·  ")).font(.callout) } }
                Section(title: "Ready for test") {
                    ForEach(store.readyForTest, id: \.0) { r in
                        HStack { Text(r.0).font(.callout); Text(r.1).font(.caption).foregroundStyle(.secondary); Spacer(); Button("Open PR") {}.controlSize(.small) }
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 720, alignment: .topLeading)
    }
}

struct Section<Content: View>: View {
    let title: String; @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content
        }
    }
}

struct IconLab: View {
    static let states: [(String, IconState)] = [
        ("stopped", IconState(connected: false, working: 0, done: 0, total: 0, attention: 0)),
        ("idle", IconState(connected: true, working: 0, done: 0, total: 0, attention: 0)),
        ("1 epic, 2/9", IconState(connected: true, working: 1, done: 2, total: 9, attention: 0)),
        ("2 epics, 8/16", IconState(connected: true, working: 2, done: 8, total: 16, attention: 0)),
        ("3 epics, 15/18", IconState(connected: true, working: 3, done: 15, total: 18, attention: 0)),
        ("2 epics + needs you", IconState(connected: true, working: 2, done: 8, total: 16, attention: 1)),
        ("idle + needs you", IconState(connected: true, working: 0, done: 0, total: 0, attention: 1)),
    ]
    func strip(_ v: IconVariant, _ s: IconState, dark: Bool) -> some View {
        let fg: NSColor = dark ? .white : .black
        return Image(nsImage: iconImage(v, s, fg: fg)).padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(dark ? Color(white: 0.17) : Color(white: 0.9)))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Menu bar icon: 3 variants x 7 states, on a light and a dark bar (drawn at 3x here, real size is 18 pt tall)").font(.caption).foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    Text("")
                    ForEach(Self.states, id: \.0) { Text($0.0).font(.caption2).foregroundStyle(.secondary).frame(width: 78, alignment: .leading) }
                }
                ForEach(IconVariant.allCases) { v in
                    GridRow {
                        Text(v.title).font(.caption).frame(width: 90, alignment: .leading)
                        ForEach(Self.states, id: \.0) { st in
                            VStack(spacing: 4) { strip(v, st.1, dark: false); strip(v, st.1, dark: true) }.frame(width: 78, alignment: .leading)
                        }
                    }
                }
            }
        }.padding(16)
    }
}

struct NotifyView: View {
    @ObservedObject var n: Notifier
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notification check (ad-hoc signed .app)").font(.headline)
            Text("bundle id: \(Bundle.main.bundleIdentifier ?? "none")   build: \(n.build)").font(.caption.monospaced())
            Text("authorization: \(n.status)").font(.body.monospaced())
            Text(n.lastResult).font(.caption.monospaced()).foregroundStyle(.secondary)
            HStack {
                Button("1. Ask permission") { n.request() }
                Button("Refresh status") { n.refresh() }
                Button("2. needs_human banner") { n.send("Carrier · needs you", "acme/web#51: review limit reached, 2 blockers left") }
                Button("ready_for_test banner") { n.send("Carrier · ready to test", "acme/api#112: PR #130 has a clean review") }
            }
            Text("Re-sign test: run ./build-app.sh again (build number goes up), reopen, and read 'authorization' above before pressing anything. 'authorized' = no new prompt.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(16).frame(width: 720, alignment: .leading)
    }
}

struct RootView: View {
    @ObservedObject var store: Store
    @ObservedObject var notifier: Notifier
    var body: some View {
        TabView {
            ScrollView { PanelView(store: store) }.tabItem { Text("Panel") }
            ScrollView { IconLab() }.tabItem { Text("Icon lab") }
            NotifyView(n: notifier).tabItem { Text("Notifications") }
        }.frame(minWidth: 760, minHeight: 560)
    }
}

/// The four motion styles of the bar icon, four frames each, on a light and a dark bar.
struct MotionLab: View {
    static let phases: [Double] = [0, 0.25, 0.5, 0.75]
    let state = IconState(connected: true, working: 2, done: 8, total: 16, attention: 0)
    func strip(_ m: IconMotion, _ p: Double, dark: Bool) -> some View {
        Image(nsImage: iconImage(.bar, state, fg: dark ? .white : .black, phase: p, motion: m))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(dark ? Color(white: 0.17) : Color(white: 0.9)))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bar icon, 2 epics working, 8/16 slices: four frames of each motion (one loop takes 1.2 s)").font(.caption).foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                ForEach(IconMotion.allCases) { m in
                    GridRow {
                        Text(m.title).font(.caption).frame(width: 120, alignment: .leading)
                        ForEach(Self.phases, id: \.self) { p in
                            VStack(spacing: 4) { strip(m, p, dark: false); strip(m, p, dark: true) }.frame(width: 80, alignment: .leading)
                        }
                    }
                }
            }
        }.padding(16)
    }
}
