import CarrierCore
import SwiftUI

/// The Agent output tab of an epic that is shipping but has no output yet: icon, title and the steps before the first agent.
struct StartingView: View {
    let steps: [StartStep]

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: "clock")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(.blue)
                .frame(width: 54, height: 54)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.blue.opacity(0.14)))
                .padding(.bottom, 9)
            Text("Starting the ship step").font(.headline)
            VStack(alignment: .leading, spacing: 9) {
                ForEach(steps, id: \.title) { step in
                    HStack(spacing: 9) {
                        mark(step.state).frame(width: 16, height: 16)
                        Text(step.title).font(.callout)
                            .foregroundStyle(step.state == .current ? Color.primary : .secondary)
                    }
                }
            }
            .padding(.top, 8)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func mark(_ state: StepState) -> some View {
        switch state {
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .current: SpinningRing(diameter: 14, lineWidth: 2)
        case .waiting, .problem: Circle().strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1.5).frame(width: 13, height: 13)
        }
    }
}
