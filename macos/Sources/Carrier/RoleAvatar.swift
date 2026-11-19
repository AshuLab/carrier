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
            let request = URLRequest(url: url, timeoutInterval: 10)
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if (response as? HTTPURLResponse)?.statusCode == 200, data.count <= Self.largest, let image = NSImage(data: data) {
                    images[appId] = image
                } else {
                    failed(appId, "it is not a usable picture")
                }
            } catch {
                // a cancelled fetch is not the bot's fault: it is asked again the next time
                if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
                failed(appId, String(describing: error))
            }
        }
    }

    private func failed(_ appId: String, _ reason: String) {
        failedAt[appId] = Date()
        NSLog("Carrier: the avatar of GitHub App %@ could not be used: %@", appId, reason)
    }
}

/// Who a role works as, as a picture: the bot's own (its GitHub App's logo) or, with none, its initials (of the bot's name) on a color; your gh login is a person; an
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
            .accessibilityHidden(true)
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: size * 0.28, style: .continuous) }

    @ViewBuilder private var face: some View {
        switch identity {
        case .forge(let bot):
            ZStack {
                Text(roleInitials(bot)).font(.scaled(size * 0.38, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: size, height: size).background(ProjectIcon.palette[projectColorIndex(bot, count: ProjectIcon.palette.count)])
                if let image = store.image(for: appId) { Image(nsImage: image).resizable().scaledToFill().frame(width: size, height: size) }
            }
            .clipShape(shape)
        case .gh:
            Glyph(.user, size: size * 0.5, bold: true).foregroundStyle(.white).frame(width: size, height: size).background(shape.fill(Color.gray))
        case .missing, .unset:
            Text("?").font(.scaled(size * 0.4, weight: .semibold)).foregroundStyle(.secondary)
                .frame(width: size, height: size).overlay(shape.strokeBorder(Color.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])))
        }
    }

    private func corner(_ account: String) -> some View {
        let diameter = max(14, size * 0.42)
        return AccountMark(account: account, icon: icon, size: diameter * 0.58)
            .foregroundStyle(.primary)
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(Color.themeWindow))
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.14), lineWidth: 1))
    }
}
