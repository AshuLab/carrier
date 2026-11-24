import AppKit
import CarrierCore
import SwiftUI

/// The icon, color and label of each account of `providers.json`, read from the file (the Providers page and the chat both look an account up
/// here): the file is read at launch, when the app comes back active and after the editor saves.
@MainActor @Observable final class ProviderIdentityStore {
    static let shared = ProviderIdentityStore()

    private(set) var accounts: [String: ProviderIdentity] = [:]
    private(set) var displayNames: [String: String] = [:]
    private init() {
        reload()
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Self.shared.reload() }
        }
    }

    func reload() {
        let json = (try? ProvidersFile.current().read()).flatMap { $0 }
        let read = providerIdentities(providersJSON: json)
        if read != accounts { accounts = read }
        let names = providerDisplayNames(providersJSON: json)
        if names != displayNames { displayNames = names }
    }

    func identity(of agent: String) -> ProviderIdentity { accounts[AgentAccounts.account(of: agent)] ?? .none }

    /// The short name of an account where there is little room: its label, else its display name, else the name it has always had.
    func shortName(of agent: String) -> String { identity(of: agent).label ?? displayNames[AgentAccounts.account(of: agent)] ?? agent }
}

extension AccountColor {
    /// The system's color of that name, which is its own for light and dark.
    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .teal: .teal
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .mint: .mint
        case .cyan: .cyan
        case .indigo: .indigo
        case .brown: .brown
        case .gray: .gray
        }
    }
}

/// The mark of an account: the icon it was given (a glyph or its first letter) or, with none, its tool's mark as `ProviderMark` draws it,
/// in the color it was given or, with none, in the one around it.
struct AccountMark: View {
    /// The account, or the chat agent that runs on it.
    let account: String
    /// What the tool's mark is looked up by when the account has no icon; the harness of the agent when not given (`AgentAccounts.harness`).
    var icon: String?
    var size: CGFloat = 14
    private let store = ProviderIdentityStore.shared

    var body: some View {
        let identity = store.identity(of: account)
        if let color = identity.color?.color { mark(identity).foregroundStyle(color) } else { mark(identity) }
    }

    @ViewBuilder private func mark(_ identity: ProviderIdentity) -> some View {
        if let symbol = identity.icon?.symbol {
            Image(systemName: symbol).font(.scaled(size * 0.86, weight: .medium)).frame(width: size, height: size)
        } else if identity.icon == .letter {
            Text(String(account.prefix(1)).uppercased()).font(.scaled(size * 0.8, weight: .bold)).frame(width: size, height: size)
        } else {
            ProviderMark(name: icon ?? AgentAccounts.harness(of: account), size: size)
        }
    }
}
