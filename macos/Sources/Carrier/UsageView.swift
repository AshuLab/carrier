import CarrierCore
import SwiftUI

/// The one Usage state the window holds, asked of the real chat host (the fixture's under `--fixture`).
enum AppUsage {
    @MainActor static let store = UsageStore(host: SocketChatHost())
}

/// The Usage page of the sidebar foot. A placeholder for now: it asks the host when it opens and says what came back; the quota and
/// consumption cards come in later slices (docs/specs/usage-and-limits.md).
struct UsageView: View {
    let store: UsageStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Usage").font(.title3.weight(.semibold))
                    Text("Limits left and what was used, per account").font(.callout).foregroundStyle(.secondary)
                }
                SettingsTabCard {
                    Group {
                        if let error = store.error {
                            Text(error).foregroundStyle(.orange).textSelection(.enabled)
                        } else if let snapshot = store.snapshot {
                            Text("\(snapshot.quotas.count) accounts and servers, \(snapshot.summary.turns) turns in the last \(store.days) days")
                        } else {
                            Text("Asking the chat host…").foregroundStyle(.secondary)
                        }
                    }
                    .font(.callout).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 14)
                }
            }
            .padding(18).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .task { await store.load() }
    }
}
