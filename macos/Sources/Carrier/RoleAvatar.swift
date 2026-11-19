import AppKit
import CarrierCore
import SwiftUI

/// The pictures of the bots of Agent Forge. The registry has no avatar of its own, but each bot is a GitHub App and its logo is public (`forgeAvatarURL`),
/// so it is fetched from there once per run (and from the system's URL cache before that), never under `--fixture`. A bot with no id, no network or a
/// reply that is not an image keeps its initials; nothing is shown as an error, since the picture is only a help to tell the roles apart.
@MainActor @Observable final class ForgeAvatarStore {
    static let shared = ForgeAvatarStore()

    private(set) var images: [String: NSImage] = [:]
    @ObservationIgnored private var tried: [String: Date] = [:]
    @ObservationIgnored private let fetches = CommandLine.arguments.contains("--fixture") == false
    private static let retryAfter: TimeInterval = 600
    private static let largest = 2_000_000

    func image(for appId: String?) -> NSImage? { appId.flatMap { images[$0] } }

    func load(_ appId: String?) async {
        guard fetches, let appId, images[appId] == nil, let url = forgeAvatarURL(appId: appId, pixels: 192) else { return }
        if let last = tried[appId], Date().timeIntervalSince(last) < Self.retryAfter { return }
        tried[appId] = Date()
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.cachePolicy = .returnCacheDataElseLoad
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= Self.largest, let image = NSImage(data: data) else {
                NSLog("Carrier: the avatar of GitHub App %@ is not a usable picture", appId)
                return
            }
            images[appId] = image
        } catch {
            NSLog("Carrier: the avatar of GitHub App %@ could not be fetched: %@", appId, String(describing: error))
        }
    }
}

/// Who a role works as, as a picture: the bot's own (its GitHub App's logo) or, with none, its initials on a color; your gh login is a person; an
/// identity that is not there is a dashed square with a question mark. The corner wears the mark of the account the role runs on, as a session's
/// avatar does (`AgentAvatar`), so which model is working is seen before it is read.
struct RoleAvatar: View {
    let identity: RoleIdentity
    /// The profile the role names: it gives the initials and the color.
    let name: String?
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
            .task(id: appId) { await store.load(appId) }
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
            Image(systemName: "person.fill").font(.scaled(size * 0.42)).foregroundStyle(.white).frame(width: size, height: size).background(shape.fill(Color.gray))
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
