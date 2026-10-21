import CarrierCore
import SwiftUI

/// The Review tab: the latest round as a card with its numbered steps, the earlier rounds folded under it, newest first.
struct ReviewTabView: View {
    let epic: EpicRef
    let model: ReviewTabModel
    @Binding var folds: ReviewFolds

    var body: some View {
        if let card = model.card {
            VStack(alignment: .leading, spacing: 10) {
                if let headline = model.headline {
                    Text(headline).font(.callout).foregroundStyle(.secondary)
                }
                ReviewCardView(card: card)
                if model.history.isEmpty == false {
                    Text("History · newest first").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 6)
                    ForEach(model.history, id: \.id) { round in
                        ReviewHistoryRow(round: round, open: folds.isOpen(epic, round.id)) { folds.toggle(epic, round.id) }
                    }
                }
            }
        } else if model.history.isEmpty {
            EmptyStateView(state: .reviewNotStarted).frame(minHeight: 260)
        } else {
            // back in ship after a requeue: only the earlier attempt's rounds
            VStack(alignment: .leading, spacing: 10) {
                Text("Review has not started again").font(.callout).foregroundStyle(.secondary)
                Text("History · newest first").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(model.history, id: \.id) { round in
                    ReviewHistoryRow(round: round, open: folds.isOpen(epic, round.id)) { folds.toggle(epic, round.id) }
                }
            }
        }
    }
}

private struct ReviewCardView: View {
    let card: ReviewCard

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(card.heading).font(.body.weight(.semibold))
                Spacer(minLength: 0)
                ReviewDeltaView(round: card.view)
                ReviewChipView(chip: card.view.chip)
            }
            ReviewStepsView(round: card.view)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.07)))
    }
}

private struct ReviewHistoryRow: View {
    let round: ReviewRoundView
    let open: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: toggle) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(open ? 90 : 0))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Round \(round.round)").font(.body.weight(.semibold))
                        Text(round.blockerCount == 0 ? "No blockers" : "\(round.blockerCount) blocker\(round.blockerCount == 1 ? "" : "s")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    ReviewDeltaView(round: round)
                    ReviewChipView(chip: round.chip)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open { ReviewStepsView(round: round).padding(.leading, 4) }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.07)))
    }
}

private struct ReviewChipView: View {
    let chip: ReviewChip

    var body: some View {
        let color: Color = switch chip.tone {
        case .good: .green
        case .live: .blue
        case .attention: .orange
        case .neutral: .secondary
        }
        Text(chip.text).font(.caption.weight(.medium)).foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.14)))
    }
}

private struct ReviewDeltaView: View {
    let round: ReviewRoundView

    var body: some View {
        if let text = round.deltaText {
            // fewer blockers is good, more is not
            Text(text).font(.caption.weight(.medium).monospacedDigit()).foregroundStyle((round.delta ?? 0) < 0 ? Color.green : .orange)
        }
    }
}

private struct ReviewStepsView: View {
    let round: ReviewRoundView

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(round.steps, id: \.number) { ReviewStepRow(step: $0) }
            if round.approximate {
                Text("Marks are approximate: the reviewer gave no blocker ids, so they come from matching titles.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct ReviewStepRow: View {
    let step: ReviewStep

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            marker
            VStack(alignment: .leading, spacing: 3) {
                Text(step.title).font(.callout.weight(.semibold)).foregroundStyle(step.state == .waiting ? .secondary : .primary)
                Text(step.subtitle).font(.caption).foregroundStyle(step.state == .stopped ? Color.orange : .secondary)
                ForEach(step.blockers, id: \.title) { ReviewBlockerRow(blocker: $0) }
                ForEach(step.commits, id: \.sha) { commit in
                    HStack(spacing: 6) {
                        Text(commit.sha).font(.caption.monospaced()).foregroundStyle(.secondary)
                        Text(commit.subject).font(.caption).lineLimit(1)
                    }
                }
                if step.moreCommits > 0 {
                    Text("+ \(step.moreCommits) more").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private var marker: some View {
        Group {
            switch step.state {
            case .done: Image(systemName: "checkmark").foregroundStyle(.white).background(Circle().fill(Color.green).frame(width: 18, height: 18))
            case .current: ProgressView().controlSize(.mini).frame(width: 18, height: 18)
            case .waiting: Text("\(step.number)").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    .frame(width: 18, height: 18).background(Circle().fill(Color.secondary.opacity(0.16)))
            case .stopped: Text("!").font(.caption.weight(.bold)).foregroundStyle(.white)
                    .frame(width: 18, height: 18).background(Circle().fill(Color.orange))
            }
        }
        .font(.caption2.weight(.bold)).frame(width: 18, height: 18)
    }
}

private struct ReviewBlockerRow: View {
    let blocker: ReviewBlocker

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle().fill(color).frame(width: 5, height: 5).offset(y: -1)
            Text(blocker.title).font(.caption).lineLimit(2)
            Spacer(minLength: 4)
            Text(blocker.mark.text + (blocker.approximate ? " ≈" : "")).font(.caption2).foregroundStyle(color).fixedSize()
        }
    }

    private var color: Color {
        switch blocker.mark {
        case .fixed: .green
        case .carriedOver, .since: .orange
        case .new: .secondary
        }
    }
}
