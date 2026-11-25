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
    func shortName(of agent: String) -> String { providerShortName(of: agent, identities: accounts, displayNames: displayNames) }
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

extension AccountMark {
    /// The mark of `account` (an account, or the chat agent that runs on it), as its identity in `providers.json` says: the icon it was given (a glyph or its
    /// first letter) or, with none, its tool's mark, in the color it was given or, with none, in the one around it. `icon` is what the tool's mark is looked
    /// up by when the account has no icon; the harness of the agent when not given.
    @MainActor init(account: String, icon: String? = nil, size: CGFloat = 14) {
        let look = accountMarkLook(of: account, identity: ProviderIdentityStore.shared.identity(of: account), icon: icon)
        self.init(symbol: look.symbol, initials: look.initials, tool: look.tool, tint: look.color?.color, size: size)
    }
}
