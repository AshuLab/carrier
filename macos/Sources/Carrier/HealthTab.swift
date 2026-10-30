import AppKit
import CarrierCore
import SwiftUI

/// The Health tab of Settings (docs/specs/health-check-in-the-app.md): the rows of `healthSections`, each with its state and, when the fixed
/// list has one, its fix. Check again asks the host for a fresh health and reads what only the app knows again. The tab has no automated test.
struct HealthTabView: View {
    let state: ConnectionState?
    private let store = AppHealth.store
    @ObservedObject private var start = StartController.shared
    @ObservedObject private var setup = SetupController.shared
    @State private var probe = CarrierProbe()
    @State private var checking = false

    /// What the app reads off the machine: the installed `carrier`'s version and the chat host's socket and version.
    private struct CarrierProbe {
        var installedVersion: String?
        var hostRunning = false
        var hostVersion: String?
    }

    var body: some View {
        let facts = CarrierFacts(
            carrierFound: setup.settings.carrier.isEmpty == false, installedVersion: probe.installedVersion,
            hostRunning: probe.hostRunning, hostVersion: probe.hostVersion,
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
            ForEach(healthSections(host: store.latest, facts: facts), id: \.title) { section in
                SettingsGroup(title: section.title) {
                    if let note = section.note {
                        Text(note).font(.callout).foregroundStyle(.secondary).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(Array(section.rows.enumerated()), id: \.offset) { index, row in
                        HealthRowView(row: row, first: index == 0)
                    }
                }
            }
        }
        .task { await read() }
    }

    private func checkAgain() async {
        checking = true
        await store.check(.refresh)
        await read()
        checking = false
    }

    private func read() async {
        let settings = setup.settings
        let command = startChatHostCommand(settings: settings, environment: ProcessInfo.processInfo.environment)
        let socket = command?.socketPath ?? chatSocketPath()
        probe = await Task.detached { () -> CarrierProbe in
            var result = CarrierProbe()
            if let command { result.installedVersion = ChatHostStarter.installedVersion(command) }
            if let client = ControlClient.connect(path: socket) {
                result.hostRunning = true
                result.hostVersion = (try? client.hello())?.version
                client.close()
            }
            return result
        }.value
    }
}

private struct HealthRowView: View {
    let row: HealthRow
    let first: Bool

    var body: some View {
        HStack(spacing: 12) {
            mark
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title).fontWeight(.medium)
                Text(row.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let tool = row.tool { HealthFixButton(tool: tool, state: row.state) }
        }
        .padding(.vertical, 10).frame(minHeight: 46)
        .overlay(alignment: .top) { Divider().opacity(first ? 0 : 1) }
        .accessibilityElement(children: .combine)
    }

    private var mark: some View {
        let (symbol, color, label): (String, Color, String) = switch row.mark {
        case .ok: ("checkmark", .green, "Ready")
        case .problem: ("exclamationmark", .orange, "Needs attention")
        case .neutral: ("questionmark", .gray, "Not known")
        }
        return Image(systemName: symbol).font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
            .frame(width: 18, height: 18).background(Circle().fill(color)).accessibilityLabel(label)
    }
}
