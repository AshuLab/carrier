import CarrierCore
import SwiftUI

/// "When it starts": the four stages of a queued epic with the agent and model of each, and a footer about the slots.
struct QueuedPlanView: View {
    let plan: QueuedPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("WHEN IT STARTS").font(.caption.weight(.semibold)).foregroundStyle(.tertiary).padding(.bottom, 6)
            ForEach(plan.rows, id: \.number) { row in
                if row.number > 1 { Divider() }
                HStack(spacing: 12) {
                    Text("\(row.number)").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        .frame(width: 22, height: 22).background(Circle().fill(Color.secondary.opacity(0.15)))
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(row.name).fontWeight(.semibold)
                            if let agent = row.agent { Text("· \([agent, row.model].compactMap { $0 }.joined(separator: " · "))").foregroundStyle(.secondary) }
                        }
                        Text(row.line).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)
            }
            Divider()
            Text(plan.footer).font(.callout).foregroundStyle(.secondary).padding(.top, 10)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.secondary.opacity(0.08)))
    }
}
