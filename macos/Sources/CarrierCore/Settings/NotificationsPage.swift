import Foundation

/// The words of the Notifications page: its groups, the rows with the line under each and the words VoiceOver reads for the two chat switches that
/// share a title with a Carrier one. What the permission row says is `NotificationPermission.text`.
public struct NotificationsPage: Equatable, Sendable {
    public let groupCarrier: String
    public let groupChat: String
    public let groupDelivery: String
    public let groupPermission: String
    public let needsAttention: PageRowText
    public let ready: PageRowText
    public let problem: PageRowText
    public let chatNeedsAttention: PageRowText
    public let chatNeedsAttentionLabel: String
    public let chatDone: PageRowText
    public let chatDoneLabel: String
    public let onlyAway: PageRowText
    public let dock: PageRowText
    public let sound: PageRowText
    public let remind: PageRowText
    public let quiet: PageRowText
    public let from: PageRowText
    public let until: PageRowText
    public let permission: String
    public let checking: String
    public let openSystemSettings: String
    public let allow: String
    public let sendTest: String
}

public func notificationsPage(bundle: Bundle? = nil, locale: Locale = .current) -> NotificationsPage {
    func row(_ title: String, _ detail: String) -> PageRowText { PageRowText(title: title, detail: detail) }
    let carrier = (
        row(Copy.notificationsNeedsAttention(bundle: bundle, locale: locale), Copy.notificationsNeedsAttentionDetail(bundle: bundle, locale: locale)),
        row(Copy.notificationsReady(bundle: bundle, locale: locale), Copy.notificationsReadyDetail(bundle: bundle, locale: locale)),
        row(Copy.notificationsProblem(bundle: bundle, locale: locale), Copy.notificationsProblemDetail(bundle: bundle, locale: locale)))
    // the chat's "Needs attention" is worded as the Carrier one: the title is the same, the line under it is its own
    let chat = (
        row(Copy.notificationsNeedsAttention(bundle: bundle, locale: locale), Copy.notificationsChatNeedsAttentionDetail(bundle: bundle, locale: locale)),
        row(Copy.notificationsChatDone(bundle: bundle, locale: locale), Copy.notificationsChatDoneDetail(bundle: bundle, locale: locale)))
    let delivery = (
        row(Copy.notificationsOnlyAway(bundle: bundle, locale: locale), Copy.notificationsOnlyAwayDetail(bundle: bundle, locale: locale)),
        row(Copy.notificationsDock(bundle: bundle, locale: locale), Copy.notificationsDockDetail(bundle: bundle, locale: locale)),
        row(Copy.notificationsSound(bundle: bundle, locale: locale), Copy.notificationsSoundDetail(bundle: bundle, locale: locale)),
        row(Copy.notificationsRemind(bundle: bundle, locale: locale), Copy.notificationsRemindDetail(bundle: bundle, locale: locale)),
        row(Copy.notificationsQuiet(bundle: bundle, locale: locale), Copy.notificationsQuietDetail(bundle: bundle, locale: locale)),
        row(Copy.notificationsFrom(bundle: bundle, locale: locale), Copy.notificationsFromDetail(bundle: bundle, locale: locale)),
        row(Copy.notificationsUntil(bundle: bundle, locale: locale), Copy.notificationsUntilDetail(bundle: bundle, locale: locale)))
    return NotificationsPage(
        groupCarrier: Copy.notificationsGroupCarrier(bundle: bundle, locale: locale), groupChat: Copy.notificationsGroupChat(bundle: bundle, locale: locale),
        groupDelivery: Copy.notificationsGroupDelivery(bundle: bundle, locale: locale), groupPermission: Copy.notificationsGroupPermission(bundle: bundle, locale: locale),
        needsAttention: carrier.0, ready: carrier.1, problem: carrier.2,
        chatNeedsAttention: chat.0, chatNeedsAttentionLabel: Copy.notificationsChatNeedsAttentionLabel(bundle: bundle, locale: locale),
        chatDone: chat.1, chatDoneLabel: Copy.notificationsChatDoneLabel(bundle: bundle, locale: locale),
        onlyAway: delivery.0, dock: delivery.1, sound: delivery.2, remind: delivery.3, quiet: delivery.4, from: delivery.5, until: delivery.6,
        permission: Copy.notificationsPermission(bundle: bundle, locale: locale), checking: Copy.notificationsChecking(bundle: bundle, locale: locale),
        openSystemSettings: Copy.notificationsOpenSystemSettings(bundle: bundle, locale: locale), allow: Copy.notificationsAllow(bundle: bundle, locale: locale),
        sendTest: Copy.notificationsSendTest(bundle: bundle, locale: locale))
}
