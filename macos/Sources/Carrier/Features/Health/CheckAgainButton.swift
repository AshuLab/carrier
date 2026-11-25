import CarrierCore
import CarrierUI
import SwiftUI

/// The button that asks again (Check again, Check now) wherever the app has one, so that they all behave alike: a check the person asked for ends in a
/// green mark and "Up to date", or a red one and "Check failed", for `CheckPhase.resultSeconds`, and then rests. A check the page ran by itself (when it
/// opens) only ends at rest. The phase is `CheckPhase`'s (`CheckPhaseTests`); `CheckButton` draws it.
struct CheckAgainButton: View {
    var skin = CheckButton.Skin.capsule
    var title = Copy.healthCheckAgain()
    /// A check is running, whoever asked for it.
    let checking: Bool
    /// How the check ended; read when `checking` turns false.
    var failed = false
    let action: () -> Void

    @State private var phase = CheckPhase.idle
    @State private var asked = false

    var body: some View {
        CheckButton(skin: skin, title: title, phase: CheckButton.Phase(phase), action: press)
            .onAppear { phase = phase.moving(checking: checking, failed: failed, asked: asked) }
            .onChange(of: checking) {
                phase = phase.moving(checking: checking, failed: failed, asked: asked)
                if checking == false { asked = false }
            }
            // the result rests after its time; a new phase cancels the wait
            .task(id: phase) {
                guard phase == .done || phase == .failed else { return }
                try? await Task.sleep(for: .seconds(CheckPhase.resultSeconds))
                if Task.isCancelled == false { phase = .idle }
            }
    }

    private func press() {
        guard phase.accepts else { return }
        asked = true
        action()
    }
}

extension CheckButton.Phase {
    init(_ phase: CheckPhase) {
        switch phase {
        case .idle: self = .idle
        case .checking: self = .checking
        case .done: self = .done
        case .failed: self = .failed
        }
    }
}
