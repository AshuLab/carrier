import CarrierCore

/// The one health the app holds: the draft reads it, and what asks again (Check again) goes through it.
enum AppHealth {
    @MainActor static let store = HealthStore(host: SocketChatHost())
}
