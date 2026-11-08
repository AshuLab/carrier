import AppKit
import CarrierCore
import SwiftUI

/// The Health tab of Settings (docs/specs/health-check-in-the-app.md): the rows of `healthSections`, each with its state and, when the fixed
/// list has one, its fix. Check again asks the host for a fresh health and reads what only the app knows again. The tab has no automated test.
struct HealthTabView: View {
    let state: ConnectionState?
    private let store = AppHealth.store
    private let doctor = AppHealth.doctor
    @ObservedObject private var start = StartController.shared
    @ObservedObject private var setup = SetupController.shared
    @State private var probe = CarrierProbe()
    @State private var checking = false

    /// What the app reads off the machine: the installed `carrier`'s version and the chat host's socket and version.
    private struct CarrierProbe {
        var installedVersion: String?
        var hostRunning = false
        var hostVersion: String?
        var hostReportsHealth = true
    }

    var body: some View {
        let facts = CarrierFacts(
            carrierFound: setup.carrierRuns, installedVersion: probe.installedVersion,
            hostRunning: probe.hostRunning, hostVersion: probe.hostVersion,
            hostReportsHealth: probe.hostReportsHealth,
            configExists: start.configExists, engineRunning: { if case .running? = state { true } else { false } }()
        )
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Is everything Carrier needs ready?").font(.callout).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if checking { ProgressView().controlSize(.small) }
                Button("Check again") { Task { await checkAgain() } }.buttonStyle(.glass).buttonBorderShape(.capsule).disabled(checking)
            }
            .padding(.horizontal, 14)
            ForEach(healthSections(host: store.latest, facts: facts, doctor: doctor.state), id: \.title) { section in
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.title.uppercased()).font(.caption2).fontWeight(.semibold).foregroundStyle(.tertiary).padding(.leading, 14).padding(.top, 8)
                    if let note = section.note {
                        Text(note).font(.callout).foregroundStyle(.secondary).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.07)))
                    }
                    // cards side by side: as many as fit, so the tab stays short
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10, alignment: .top)], alignment: .leading, spacing: 10) {
                        ForEach(Array(section.rows.enumerated()), id: \.offset) { _, row in HealthCardView(row: row) }
                    }
                }
            }
        }
        .task {
            runDoctor()
            await read()
        }
        // back from Terminal, where `carrier` may have just been installed: it is looked for on the disk again
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Task { await read() } }
    }

    /// Not awaited: the layer says it is running and the rest of the tab stays usable. The store ignores a run while one is running.
    private func runDoctor() {
        let settings = setup.settings, carrier = setup.carrier, configExists = start.configExists
        Task { await doctor.check(settings: settings, carrier: carrier, environment: ProcessInfo.processInfo.environment, configExists: configExists) }
    }

    private func checkAgain() async {
        checking = true
        runDoctor()
        await store.check(.refresh)
        await read()
        checking = false
    }

    private func read() async {
        let settings = setup.settings, carrier = setup.carrier
        let command = startChatHostCommand(settings: settings, carrier: carrier, environment: ProcessInfo.processInfo.environment)
        let socket = command?.socketPath ?? chatSocketPath()
        probe = await Task.detached { () -> CarrierProbe in
            var result = CarrierProbe()
            if let command { result.installedVersion = ChatHostStarter.installedVersion(command) }
            if let client = ControlClient.connect(path: socket) {
                result.hostRunning = true
                let hello = try? client.hello()
                result.hostVersion = hello?.version
                result.hostReportsHealth = hello?.capabilities.contains(.health) ?? true
                client.close()
            }
            return result
        }.value
    }
}

/// One check as a card: its mark and name, what it says and, when the fixed list has one, its fix.
private struct HealthCardView: View {
    let row: HealthRow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                mark
                Text(row.title).fontWeight(.medium).lineLimit(2)
            }
            if row.detail.isEmpty == false {
                Text(row.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let fix = row.fix {
                Text("Fix: \(fix)").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let tool = row.tool { HealthFixButton(tool: tool, state: row.state) }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.07)))
        .accessibilityElement(children: .combine)
    }

    private var mark: some View {
        let (symbol, color, label): (String, Color, String) = switch row.mark {
        case .ok: ("checkmark", .green, "Ready")
        case .warning: ("exclamationmark", .yellow, "Warning")
        case .problem: ("exclamationmark", .orange, "Needs attention")
        case .neutral: ("questionmark", .gray, "Not known")
        }
        return Image(systemName: symbol).font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
            .frame(width: 18, height: 18).background(Circle().fill(color)).accessibilityLabel(label)
    }
}
