import CarrierCore
import SwiftUI

/// An agent's JSON message as a report: a slice report as a card (outcome, pull request, branch, the definition of done, the
/// note), any other object as a labelled list.
struct JSONMessageView: View {
    let message: JSONMessage

    var body: some View {
        switch message {
        case .slice(let report): SliceReportView(report: report)
        case .fields(let fields): FieldsView(fields: fields)
        }
    }
}

private struct SliceReportView: View {
    let report: SliceReport

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let title = report.title { Text(title).font(.system(size: 14, weight: .semibold)) }
                pill
                Spacer(minLength: 8)
                if let pull = report.pull {
                    Link(destination: pull.url) {
                        Label(pull.label, systemImage: "arrow.triangle.pull").font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain).foregroundStyle(.blue)
                }
            }
            if let branch = report.branch {
                Label(branch, systemImage: "arrow.triangle.branch")
                    .font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(Color.secondary.opacity(0.14)))
            }
            let done = report.checks.filter(\.passed).count
            Text("DEFINITION OF DONE · \(done) OF \(report.checks.count)")
                .font(.system(size: 11, weight: .semibold)).tracking(0.4).foregroundStyle(.tertiary).padding(.top, 6)
            ChecklistView(checks: report.checks)
            if let note = report.note { MarkdownView(text: note).foregroundStyle(.secondary).padding(.top, 6) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var pill: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold))
            Text(report.outcome)
        }
        .font(.caption.weight(.semibold)).foregroundStyle(tint)
        .padding(.horizontal, 10).padding(.vertical, 3).background(Capsule().fill(tint.opacity(0.18)))
    }

    private var icon: String {
        switch report.tone {
        case .good: "checkmark.circle"
        case .warning: "exclamationmark.triangle"
        case .stop: "person"
        }
    }

    private var tint: Color {
        switch report.tone {
        case .good: .green
        case .warning: .orange
        case .stop: .red
        }
    }
}

private struct ChecklistView: View {
    let checks: [ReportCheck]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(checks.enumerated()), id: \.offset) { _, check in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Image(systemName: check.passed ? "checkmark.circle" : "xmark.circle")
                        .foregroundStyle(check.passed ? Color.green : Color.red)
                    Text(check.name).foregroundStyle(check.passed ? .secondary : .primary)
                }
            }
        }
    }
}

private struct FieldsView: View {
    let fields: [JSONField]

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 7) {
            ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                GridRow {
                    Text(field.label).font(.caption).foregroundStyle(.tertiary).gridColumnAlignment(.leading)
                    value(field.value).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func value(_ value: JSONField.Value) -> some View {
        switch value {
        case .flag(let on):
            Label(on ? "yes" : "no", systemImage: on ? "checkmark.circle" : "xmark.circle")
                .font(.caption.weight(.semibold)).foregroundStyle(on ? Color.green : Color.red)
        case .number(let text): Text(text).fontWeight(.semibold)
        case .text(let text): Text(text).foregroundStyle(.secondary).textSelection(.enabled)
        case .code(let text):
            Text(text).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
        case .link(let link): Link(link.label, destination: link.url).foregroundStyle(.blue)
        case .list(let items):
            VStack(alignment: .leading, spacing: 2) { ForEach(Array(items.enumerated()), id: \.offset) { _, item in Text("· \(item)") } }
        case .checks(let checks): ChecklistView(checks: checks)
        }
    }
}
