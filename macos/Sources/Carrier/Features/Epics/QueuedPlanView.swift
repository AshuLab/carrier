import CarrierCore
import SwiftUI

/// "When it starts": the four stages of a queued epic with the agent and model of each, and a footer about the slots.
struct QueuedPlanView: View {
    let plan: QueuedPlan

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.none) {
            Text("WHEN IT STARTS").font(.caption.weight(.semibold)).foregroundStyle(.tertiary).padding(.bottom, Tokens.Space.s6)
            ForEach(plan.rows, id: \.number) { row in
                if row.number > 1 { Divider() }
                HStack(spacing: Tokens.Space.s12) {
                    Text("\(row.number)").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        .frame(width: 22, height: 22).background(Circle().fill(Color.secondary.opacity(0.15)))
                    VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                        HStack(spacing: Tokens.Space.s4) {
                            Text(row.name).fontWeight(.semibold)
                            if let agent = row.agent { Text("· \([agent, row.model].compactMap { $0 }.joined(separator: " · "))").foregroundStyle(.secondary) }
                        }
                        Text(row.line).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, Tokens.Space.s8)
            }
            Divider()
            Text(plan.footer).font(.callout).foregroundStyle(.secondary).padding(.top, Tokens.Space.s10)
        }
        .padding(.horizontal, Tokens.Space.s14).padding(.vertical, Tokens.Space.s12)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.panel).fill(Color.secondary.opacity(0.08)))
    }
}
