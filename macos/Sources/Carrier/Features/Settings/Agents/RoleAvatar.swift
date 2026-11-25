import AppKit
import CarrierCore
import SwiftUI

/// The pictures of the bots of Agent Forge. The registry has no avatar of its own, but each bot is a GitHub App and its logo is public (`forgeAvatarURL`),
/// so it is fetched from there, once per run (the system's URL cache decides what asks GitHub again), never under `--fixture`. A bot with no id, no
/// network or a reply that is not an image keeps its initials; nothing is shown as an error, since the picture is only a help to tell the roles apart.
/// A fetch is a task of the store's, one per id, and not of the view that asked: going from the first screen to a role's screen, which removes
/// that view, does not cancel it.
@MainActor @Observable final class ForgeAvatarStore {
    static let shared = ForgeAvatarStore()

    private(set) var images: [String: NSImage] = [:]
    /// The picture of the person's own gh login.
    private(set) var userImage: NSImage?
    @ObservationIgnored private var failedAt: [String: Date] = [:]
    @ObservationIgnored private var inflight: Set<String> = []
    @ObservationIgnored private let fetches = CommandLine.arguments.contains("--fixture") == false
    private static let retryAfter: TimeInterval = 600
    private static let largest = 2_000_000

    func image(for appId: String?) -> NSImage? { appId.flatMap { images[$0] } }

    /// Starts the fetch of a bot's picture unless it is there, on its way, or failed less than ten minutes ago.
    func fetch(_ appId: String?) {
        guard fetches, let appId, images[appId] == nil, inflight.contains(appId) == false, let url = forgeAvatarURL(appId: appId, pixels: 192) else { return }
        if let last = failedAt[appId], Date().timeIntervalSince(last) < Self.retryAfter { return }
        inflight.insert(appId)
        Task {
            defer { inflight.remove(appId) }
            do {
                if let image = try await Self.picture(url) { images[appId] = image } else { failed(appId, "it is not a usable picture") }
            } catch {
                // a cancelled fetch is not the bot's fault: it is asked again the next time
                if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
                failed(appId, String(describing: error))
            }
        }
    }

    /// The picture of the person's own `gh` login, for the roles that run as them. The chat host knows the login (it reads it for the repository list), the
    /// picture is the public one of that account. Same rules as a bot's: once per run, a failure is tried again after ten minutes, nothing is shown as an error.
    func fetchUser() {
        let key = "gh login"
        guard fetches, userImage == nil, inflight.contains(key) == false else { return }
        if let last = failedAt[key], Date().timeIntervalSince(last) < Self.retryAfter { return }
        inflight.insert(key)
        Task {
            defer { inflight.remove(key) }
            do {
                let host = SocketChatHost()
                guard try await host.capabilities().contains(.githubRepos), let login = try await host.githubRepos(page: 1).login,
                      isGithubLogin(login), let url = URL(string: "https://avatars.githubusercontent.com/\(login)?s=192")
                else { return failed(key, "the host does not say the login") }
                if let image = try await Self.picture(url) { userImage = image } else { failed(key, "it is not a usable picture") }
            } catch {
                if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
                failed(key, String(describing: error))
            }
        }
    }

    /// The image at `url`, nil when the reply is not a usable one.
    private static func picture(_ url: URL) async throws -> NSImage? {
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 10))
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= largest else { return nil }
        return NSImage(data: data)
    }

    private func failed(_ appId: String, _ reason: String) {
        failedAt[appId] = Date()
        NSLog("Carrier: the avatar of %@ could not be used: %@", appId, reason)
    }
}

/// Who a role works as, as a picture: the bot's own (its GitHub App's logo) or, with none, its initials (of the bot's name) on a color; your gh login is your own GitHub picture, a person while it is not there; an
/// identity that is not there is a dashed square with a question mark. The corner wears the mark of the account the role runs on, as a session's
/// avatar does (`AgentAvatar`), so which model is working is seen before it is read.
struct RoleAvatar: View {
    let identity: RoleIdentity
    /// The GitHub App id of the bot, when the registry has one.
    var appId: String?
    /// The account the role runs on and its harness's icon, for the corner.
    var account: String?
    var icon: String?
    var size: CGFloat = 38
    /// The Lead reviewer while it is off.
    var off = false
    private let store = ForgeAvatarStore.shared

    var body: some View {
        face
            .frame(width: size, height: size)
            .overlay(alignment: .bottomTrailing) { if let account, off == false { corner(account).offset(x: size * 0.1, y: size * 0.1) } }
            .opacity(off ? 0.45 : 1)
            .task(id: appId) { store.fetch(appId) }
            .task(id: identity) { if identity == .gh { store.fetchUser() } }
            .accessibilityHidden(true)
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: size * 0.28, style: .continuous) }

    @ViewBuilder private var face: some View {
        switch identity {
        case .forge(let bot):
            ZStack {
                Text(roleInitials(bot)).scaledFont(size * 0.38, weight: .semibold).foregroundStyle(.white)
                    .frame(width: size, height: size).background(ProjectIcon.palette[projectColorIndex(bot, count: ProjectIcon.palette.count)])
                if let image = store.image(for: appId) { Image(nsImage: image).resizable().scaledToFill().frame(width: size, height: size) }
            }
            .clipShape(shape)
        case .gh:
            ZStack {
                Glyph(.user, size: size * 0.5, bold: true).foregroundStyle(.white).frame(width: size, height: size).background(shape.fill(Color.gray))
                if let image = store.userImage { Image(nsImage: image).resizable().scaledToFill().frame(width: size, height: size) }
            }
            .clipShape(shape)
        case .missing, .unset:
            Text("?").scaledFont(size * 0.4, weight: .semibold).foregroundStyle(.secondary)
                .frame(width: size, height: size).overlay(shape.strokeBorder(Color.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])))
        }
    }

    private func corner(_ account: String) -> some View {
        let diameter = max(14, size * 0.42)
        return AccountMark(account: account, icon: icon, size: diameter * 0.58)
            .foregroundStyle(.primary)
            .frame(width: diameter, height: diameter)
            .avatarCornerDisc()
    }
}
