import AppKit
import CarrierCore
import ServiceManagement
import SwiftUI

// The page pattern of Settings (a header, cards of rows, a preview, a Reset) and the General and Notifications pages.

/// A row of these tabs: a title and a line under it on the left, the control on the right.
struct SettingsTabRow<Control: View>: View {
    let title: String
    let detail: String
    var first = false
    var mono = false
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).fontWeight(.medium)
                Text(detail).font(mono ? .system(size: 11.5, design: .monospaced) : .caption).foregroundStyle(.secondary)
                    .lineLimit(2).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            control
        }
        .padding(.vertical, 10).frame(minHeight: 46)
        .overlay(alignment: .top) { Divider().opacity(first ? 0 : 1) }
    }
}

struct SettingsTabCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.07)))
    }
}

/// A group of a tab: a small uppercase title over a card of rows.
struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.caption2).fontWeight(.semibold).foregroundStyle(.tertiary).padding(.leading, 14).padding(.top, 8)
            SettingsTabCard { content }
        }
    }
}

/// The top of a page: an icon, the title and a line.
struct SettingsPageHeader: View {
    let page: SettingsPage

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: page.icon)
                .font(.system(size: 16, weight: .medium)).foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.16)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(page.rawValue).font(.title3.weight(.semibold))
                Text(page.detail).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

/// What goes under a page's header: the cards, a preview of what a control changes where there is one, and a Reset row where the
/// page has many controls.
struct SettingsPageBody<Content: View, Preview: View>: View {
    var reset: (() -> Void)?
    @ViewBuilder var preview: Preview
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
            preview
            if let reset {
                SettingsTabCard {
                    SettingsTabRow(title: "Reset", detail: "Puts this page back to how it came", first: true) {
                        Button("Reset", action: reset).buttonStyle(.glass).buttonBorderShape(.capsule)
                    }
                }
            }
        }
    }
}

extension SettingsPageBody where Preview == EmptyView {
    init(reset: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.init(reset: reset, preview: { EmptyView() }, content: content)
    }
}

struct GeneralTabView: View {
    @AppStorage(AppPreferences.styleKey) private var style = AppPreferences.defaultStyle.rawValue
    @AppStorage(AppPreferences.animatesKey) private var animates = AppPreferences.defaultAnimates
    @AppStorage(showEpicsKey) private var showsEpics = AppPreferences.defaultShowsEpics
    @AppStorage(AppPreferences.confirmStopKey) private var confirmStop = AppPreferences.defaultConfirmStop

    var body: some View {
        SettingsPageBody(reset: { AppPreferences().reset(.general) }) {
            SettingsGroup(title: "Menu bar") {
                SettingsTabRow(title: "Icon style", detail: "What the icon in the menu bar shows", first: true) {
                    // a saved value that is not a style reads as the default, as the icon does
                    Picker("Icon style", selection: Binding(
                        get: { IconStyle(rawValue: style) ?? AppPreferences.defaultStyle },
                        set: { style = $0.rawValue }
                    )) {
                        ForEach(IconStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
                SettingsTabRow(title: "Animate the icon", detail: "A segment moves over the bar while epics run") {
                    Toggle("Animate the icon", isOn: $animates).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(title: "List epics in the menu", detail: "The epics that run or wait show under the status") {
                    Toggle("List epics in the menu", isOn: $showsEpics).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsGroup(title: "Confirmations") {
                SettingsTabRow(title: "Ask before stopping Carrier", detail: "Only when stopping would interrupt epics that are running", first: true) {
                    Toggle("Ask before stopping Carrier", isOn: $confirmStop).labelsHidden().toggleStyle(.switch)
                }
            }
        }
    }
}

struct NotificationsTabView: View {
    @AppStorage(notifyNeedsYouKey) private var needsYou = true
    @AppStorage(notifyReadyForTestKey) private var readyForTest = true
    @AppStorage(notifyProblemKey) private var problem = false
    @AppStorage(notifyOnlyWhenAwayKey) private var onlyWhenAway = true
    @State private var permission: NotificationPermission?
    @State private var testAdvice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsGroup(title: "What to tell me") {
                SettingsTabRow(title: "Needs you", detail: "An epic stopped and waits for a person", first: true) {
                    Toggle("Needs you", isOn: $needsYou).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(title: "Ready for test", detail: "An epic finished and has a PR to try") {
                    Toggle("Ready for test", isOn: $readyForTest).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(title: "A problem", detail: "GitHub refuses a repo, or Carrier stops by itself") {
                    Toggle("A problem", isOn: $problem).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsGroup(title: "How") {
                SettingsTabRow(title: "Only when Carrier is not in front", detail: "No banner while its window is the one you are looking at", first: true) {
                    Toggle("Only when Carrier is not in front", isOn: $onlyWhenAway).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsGroup(title: "Permission") {
                SettingsTabRow(title: "System permission", detail: permission?.text ?? "Checking…", first: true) {
                    HStack {
                        if permission != .noBundle {
                            Button("Open System Settings") { NSWorkspace.shared.open(Self.systemSettingsURL) }
                        }
                        if permission == .notAsked {
                            Button("Allow") { send() }.buttonStyle(PrimaryCapsuleButtonStyle())
                        }
                        Button("Send a test") { send() }.disabled(permission == .noBundle)
                    }
                }
            }
            if let testAdvice {
                Label(testAdvice, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange).padding(.horizontal, 14)
            }
            Text("Sound and the style of the banner are set per app in System Settings › Notifications › Carrier.")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 14)
        }
        .buttonStyle(.glass).buttonBorderShape(.capsule)
        .task { refresh() }
        // back from System Settings, where the person may have changed the answer
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private static let systemSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!

    /// A test that macOS would swallow says why instead; otherwise it is sent (the first one also asks for the permission).
    private func send() {
        testAdvice = permission?.testAdvice
        guard testAdvice == nil else { return }
        SystemNotificationCentre.shared.sendTest()
    }

    private func refresh() {
        readPermission(bundleIdentifier: Bundle.main.bundleIdentifier, reader: SystemNotificationCentre.shared) {
            permission = $0
            if $0.testAdvice == nil { testAdvice = nil }
        }
    }
}
