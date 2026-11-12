import CryptoKit
import Foundation

/// What a draft lists for each chat agent (models, reasoning, access, the commands to invoke), kept so it shows at once and the host is asked
/// in the background: in memory while the app runs and in a file in the app's cache folder, so the next launch has them before anyone asks.
/// What was kept is dropped when the accounts or the chat agents change (`fingerprint`), since another account can offer other models.
@MainActor public final class AgentOfferStore {
    private struct Saved: Codable {
        var fingerprint: String
        var offers: [String: AgentOffer]
    }

    /// The app's store: its file is in the cache folder, and none under `--fixture`, which must not touch what a real run kept.
    public static let shared = AgentOfferStore(
        file: CommandLine.arguments.contains("--fixture") ? nil : defaultFile, fingerprint: { agentOfferFingerprint(carrierFolder: currentCarrierFolder()) }
    )

    public static var defaultFile: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("dev.ashulab.carrier", isDirectory: true).appendingPathComponent("agent-offers.json")
    }

    private let file: URL?
    private let fingerprint: () -> String
    private var kept: Saved
    private var asking: [String: Task<AgentOffer, Error>] = [:]

    /// A store with no file keeps its offers in memory only.
    public init(file: URL? = nil, fingerprint: @escaping () -> String = { "" }) {
        self.file = file
        self.fingerprint = fingerprint
        let saved = file.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(Saved.self, from: $0) }
        kept = saved ?? Saved(fingerprint: fingerprint(), offers: [:])
    }

    /// What was kept for the agent, nil when nothing was or the accounts changed since.
    public func offer(_ agent: String) -> AgentOffer? {
        dropIfChanged()
        return kept.offers[agent]
    }

    /// Asks the host and keeps the answer, on disk too; one that fails leaves what was kept. Asking again while an answer is awaited shares it.
    @discardableResult public func refresh(_ agent: String, host: ChatHost) async throws -> AgentOffer {
        if let running = asking[agent] { return try await running.value }
        dropIfChanged()
        let task = Task { try await host.agentOptions(agent) }
        asking[agent] = task
        defer { asking[agent] = nil }
        let offer = try await task.value
        guard kept.offers[agent] != offer else { return offer }
        kept.offers[agent] = offer
        save()
        return offer
    }

    /// Asks for every agent the host has a binary for, all at once: what the app does when it opens.
    public func warm(host: ChatHost) async {
        guard let agents = try? await host.agents() else { return }
        await withTaskGroup(of: Void.self) { group in
            for agent in agents where agent.found { group.addTask { @MainActor in _ = try? await self.refresh(agent.name, host: host) } }
        }
    }

    private func dropIfChanged() {
        let now = fingerprint()
        guard kept.fingerprint != now else { return }
        kept = Saved(fingerprint: now, offers: [:])
        save()
    }

    private func save() {
        guard let file, let data = try? JSONEncoder().encode(kept) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}

/// Stands for the accounts and the chat agents: a digest of `providers.json` and `chat/chat.json` in the Carrier folder, so a change to
/// either gives another value. A file that is not there counts as empty.
public func agentOfferFingerprint(carrierFolder: String) -> String {
    let folder = URL(fileURLWithPath: carrierFolder)
    var digest = SHA256()
    for path in ["providers.json", "chat/chat.json"] {
        digest.update(data: (try? Data(contentsOf: folder.appendingPathComponent(path))) ?? Data())
        digest.update(data: Data([0]))
    }
    return digest.finalize().map { String(format: "%02x", $0) }.joined()
}
