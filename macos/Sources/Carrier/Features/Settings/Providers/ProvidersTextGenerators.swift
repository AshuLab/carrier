import AppKit
import CarrierCore
import CarrierUI
import SwiftUI

// The Text generators group of the Providers page: the model that writes text for Carrier, and the titles of earlier sessions.

extension ProvidersTabView {
    /// The model that writes text for Carrier, chosen among the models the local servers list; `ProvidersStore.chooseTextGenerator` writes it. A server
    /// that does not answer or has no model says so and cannot be chosen; a host that does not list `textGenerators` is told to update and offers nothing.
    @ViewBuilder func textGeneratorsGroup(_ page: ProvidersPage) -> some View {
        SettingsGroup(id: "text-generators", title: Copy.providersGroupGenerators(), footer: Copy.providersGeneratorsFooter()) {
            SettingsTabRow(title: Copy.providersInUse(), detail: page.generatorInUse() ?? Copy.providersNoneChosen(), first: true) {
                if page.textGenerator != nil, store.generatorEditable {
                    Button { Task { await store.chooseTextGenerator(nil) } } label: { Label(Copy.providersClear(), icon: .close) }
                        .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small).fixedSize().help(Copy.providersClearHelp())
                }
            }
            if store.generatorEditable {
                ForEach(page.servers) { server in
                    SettingsTabRow(
                        title: server.title, detail: server.generatorNote() ?? Copy.providersChooseModel(),
                        leading: AnyView(ProviderTile(icon: nil, symbol: server.id == "ollama" ? .server : .desktop))
                    ) {
                        if server.generatorNote() == nil { generatorChoice(server) }
                    }
                }
                if page.textGenerator != nil, store.canRegenerateTitles {
                    retitleEarlierRow
                }
            } else {
                // the installed carrier would refuse the whole file with these keys in it, so they are not offered until it is updated
                SettingsTabRow(title: Copy.providersChoosingUnavailable(), detail: Copy.providersChoosingUnavailableDetail()) {
                    Glyph(.refresh).foregroundStyle(.secondary).accessibilityHidden(true)
                }
            }
        }
        if let problem = store.editProblem { SettingsGroup(title: "") { ProblemLine(text: problem, size: 11) } }
        if let note = store.editNote {
            SettingsGroup(title: "") { Label(note, icon: .info).scaledFont(11).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
    }

    /// The server's models and, first, Not used: the one in use shows chosen on its server, and Not used on it clears the choice.
    private func generatorChoice(_ server: ProviderServer) -> some View {
        ChoicePopUp(
            label: Copy.providersModelOf(server: server.title),
            options: [(value: "", title: Copy.providersNotUsedChoice())] + server.generatorModels.map { (value: $0, title: $0) },
            selection: Binding(
                get: { server.generatorModel ?? "" },
                set: { model in
                    if model.isEmpty == false { Task { await store.chooseTextGenerator((server: server.id, model: model)) } }
                    else if server.generatorModel != nil { Task { await store.chooseTextGenerator(nil) } }
                }
            )
        )
    }

    private var retitleEarlierRow: some View {
        let detail = switch store.retitleOutcome {
        case .started?: store.retitleOutcome!.words()
        case .refused?, nil: Copy.providersTitlesDetail()
        }
        let problem: String? = if case .refused(let reason) = store.retitleOutcome { reason } else { nil }
        return SettingsTabRow(id: "titles-of-earlier-sessions", title: Copy.providersTitlesTitle(), detail: detail, problem: problem) {
            HStack(spacing: Tokens.Space.s8) {
                if store.retitling {
                    ProgressView().controlSize(.small).accessibilityLabel(Copy.providersStarting())
                }
                Button {
                    Task {
                        await store.regenerateTitles()
                        if let words = store.retitleOutcome?.words() { AccessibilityNotification.Announcement(words).post() }
                    }
                } label: {
                    Label(Copy.providersWriteTitles(), icon: .sparkles)
                }
                .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small).fixedSize()
                .disabled(store.retitling)
                .help(Copy.providersWriteTitlesHelp())
            }
        }
    }
}
