import CarrierCore
import SwiftUI

/// The Overview's Carrier box and the watched repositories; a thin mapping of `carrierBox(_:)`.
struct CarrierBoxView: View {
    let snapshot: PanelSnapshot

    var body: some View {
        let box = carrierBox(snapshot)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(box.title, systemImage: "circle.fill").foregroundStyle(.green).font(.headline)
                Text(box.uptime).foregroundStyle(.secondary)
            }
            if let problem = box.problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            ForEach(box.rows, id: \.label) { row in
                KeyValue(label: row.label) { Text(row.value).monospacedDigit() }
            }
            KeyValue(label: "Intake") {
                HStack(spacing: 8) {
                    Text(box.intake.value)
                    Button(box.intake.actionTitle) { Self.send(box.intake.command) }.buttonStyle(.link)
                }
            }
        }
        .card()
        if box.repoCount > 0 {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Watched repositories").font(.headline)
                    Text("\(box.repoCount)").foregroundStyle(.secondary)
                }
                ForEach(box.repos, id: \.name) { repo in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Image(systemName: "circle.fill").font(.system(size: 7)).foregroundStyle(repo.ok ? Color.green : Color.red)
                            Text(repo.name)
                            Spacer()
                            Text(repo.lastCheck).foregroundStyle(.secondary)
                        }
                        if let error = repo.error { Text(error).font(.caption).foregroundStyle(.red) }
                    }
                }
            }
            .card()
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
    }
}

private extension View {
    func card() -> some View {
        padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
    }
}
