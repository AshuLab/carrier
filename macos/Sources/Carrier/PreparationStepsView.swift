import CarrierCore
import SwiftUI

/// The steps of a session's preparation at the top of its conversation: each one running, done or failed, with its line, git's progress
/// under the running one and the reason under the one that failed.
struct PreparationStepsView: View {
    let steps: [StepRow]
    let preparation: ChatSession.Preparation?
    /// What the host refused when asked to try again or to cancel, in words.
    let refusal: String?
    let retry: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(steps) { row in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    mark(row.status).frame(width: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.line).font(.callout)
                        if let note = row.reason ?? row.progress {
                            Text(note).font(.subheadline).foregroundStyle(row.status == .failed ? Color.red : .secondary).textSelection(.enabled)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if let refusal { Text(refusal).font(.subheadline).foregroundStyle(.red).textSelection(.enabled) }
            switch preparation {
            case .failed: Button("Try again", action: retry).buttonStyle(.glassProminent).buttonBorderShape(.capsule)
            case .running: Button("Cancel", action: cancel).buttonBorderShape(.capsule)
            case nil: EmptyView()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.10)))
    }

    @ViewBuilder private func mark(_ status: StepRow.Status) -> some View {
        switch status {
        case .running: ProgressView().controlSize(.small)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }
}
