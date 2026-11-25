import CarrierCore
import CarrierUI
import SwiftUI

/// Where the session changed agent, in the feed: a fine line across, and on it a glass capsule with the agent it was and the one it is, each with its mark, its
/// name and the model it runs, as the person set them up in `providers.json` (the account's icon, color and label); under it, quieter, what the new one has of the
/// conversation (`handoffDetail`). It splits the conversation at the exact message the change came with.
struct AgentSwitchDivider: View {
    let switched: ChatEvent.Switched
    private let store = ProviderIdentityStore.shared

    var body: some View {
        VStack(spacing: Tokens.Space.s8) {
            HStack(spacing: Tokens.Space.s12) {
                line
                HStack(spacing: Tokens.Space.s10) {
                    side(switched.from, model: switched.fromModel)
                    Glyph(.arrowRight, size: 10, bold: true).foregroundStyle(.secondary).accessibilityHidden(true)
                    side(switched.to, model: switched.toModel)
                }
                .padding(.horizontal, Tokens.Space.s14).padding(.vertical, Tokens.Space.s6)
                .chatSurface(.regular, flat: Color.primary.opacity(0.07), in: Capsule())
                line
            }
            Text(handoffDetail(to: store.shortName(of: switched.to))).scaledFont(11.5).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled).padding(.horizontal, Tokens.Space.s24)
        }
        .padding(.vertical, Tokens.Space.s6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Copy.chatSwitchSpoken(from: spoken(switched.from, switched.fromModel), to: spoken(switched.to, switched.toModel), detail: handoffDetail(to: store.shortName(of: switched.to))))
    }

    private var line: some View { Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 1) }

    /// An agent as its account says it: the mark in its color, its label in the same color, and the model beside it, quiet.
    private func side(_ agent: String, model: String?) -> some View {
        let color = store.identity(of: agent).color?.color
        return HStack(spacing: Tokens.Space.s6) {
            AccountMark(account: agent, size: 13).accessibilityHidden(true)
            Text(store.shortName(of: agent)).scaledFont(12, weight: .semibold).foregroundStyle(color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.primary)).lineLimit(1)
            if let name = modelName(model) { Text(name).scaledFont(11.5).foregroundStyle(.secondary).lineLimit(1) }
        }
    }

    private func modelName(_ model: String?) -> String? { TurnSummary(model: model).shortModel }

    private func spoken(_ agent: String, _ model: String?) -> String { [store.shortName(of: agent), modelName(model)].compactMap { $0 }.joined(separator: ", ") }
}
