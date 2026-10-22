import CarrierCore
import SwiftUI

/// The Overview's Carrier box and the watched repositories; a thin mapping of `carrierBox(_:)`.
struct CarrierBoxView: View {
    let snapshot: PanelSnapshot

    var body: some View {
        let box = carrierBox(snapshot)
        VStack(alignment: .leading, spacing: 8) {
            OverviewTitle(title: "Carrier")
            OverviewCard {
                HStack {
                    Label(box.title, systemImage: "circle.fill").labelStyle(StatusPillStyle()).font(.caption.weight(.semibold))
                    Spacer()
                    Text(box.uptime).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                .padding(.vertical, 11)
                if let problem = box.problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).padding(.vertical, 8)
                }
                ForEach(box.rows, id: \.label) { row in
                    KeyValue(label: row.label) { Text(row.value).fontWeight(.semibold).monospacedDigit() }
                }
                KeyValue(label: "Intake") {
                    HStack(spacing: 8) {
                        Text(box.intake.value).fontWeight(.semibold)
                        Button(box.intake.actionTitle) { Self.send(box.intake.command) }.buttonStyle(.link)
                    }
                }
            }
        }
        if box.repoCount > 0 {
            VStack(alignment: .leading, spacing: 8) {
                OverviewTitle(title: "Watched repositories", detail: "\(box.repoCount)")
                OverviewCard {
                    ForEach(box.repos, id: \.name) { repo in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 10) {
                                Image(systemName: "circle.fill").font(.system(size: 7)).foregroundStyle(repo.ok ? Color.green : Color.red)
                                Text(repo.name).fontWeight(.medium)
                                Spacer()
                                Text(repo.lastCheck).font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                            if let error = repo.error { Text(error).font(.caption).foregroundStyle(.red) }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }

    private static func send(_ command: Command) {
        let path = controlSocketPath()
        DispatchQueue.global().async {
            do { try CarrierCore.send(command, socketPath: path) } catch {
                FileHandle.standardError.write(Data("carrier: \(command.rawValue) failed: \(error)\n".utf8))
            }
        }
    }
}

private struct KeyValue<Value: View>: View {
    let label: String
    @ViewBuilder let value: Value

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            value
        }
        .font(.callout)
        .padding(.vertical, 8)
    }
}

/// The green pill that says Carrier is running: a dot and the text on a tinted capsule.
private struct StatusPillStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 6))
            configuration.title
        }
        .foregroundStyle(.green)
        .padding(.horizontal, 9).padding(.vertical, 3)
        .background(Capsule().fill(Color.green.opacity(0.18)))
    }
}
