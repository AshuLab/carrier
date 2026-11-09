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
                Text(detail).font(mono ? .scaled(11.5, design: .monospaced) : .caption).foregroundStyle(.secondary)
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
                .font(.scaled(16, weight: .medium)).foregroundStyle(Color.accentColor)
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
    /// An age and a time of day as the two settings write them now: 11 minutes ago, and the clock of that moment.
    private func displayPreview() -> some View {
        let now = Date()
        let format = TimeFormat.stored()
        return SettingsGroup(title: "Preview") {
            SettingsTabRow(title: "Updated 11 minutes ago", detail: "As an age or a clock time shows on a session row", first: true) {
                Text(timeText(now.addingTimeInterval(-660), now: now, format: format)).monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }

    @AppStorage(AppPreferences.styleKey) private var style = AppPreferences.defaultStyle.rawValue
    @AppStorage(AppPreferences.animatesKey) private var animates = AppPreferences.defaultAnimates
    @AppStorage(showEpicsKey) private var showsEpics = AppPreferences.defaultShowsEpics
    @AppStorage(AppPreferences.confirmStopKey) private var confirmStop = AppPreferences.defaultConfirmStop
    @AppStorage(AppPreferences.timeStyleKey) private var timeStyle = TimeStyle.relative.rawValue
    @AppStorage(AppPreferences.clockHoursKey) private var clockHours = ClockHours.system.rawValue

    var body: some View {
        SettingsPageBody(reset: { AppPreferences().reset(.general) }, preview: displayPreview) {
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
            SettingsGroup(title: "Display") {
                SettingsTabRow(title: "Time format", detail: "Ages read \"11m\", or as the time of the event, \"14:32\"", first: true) {
                    // a saved value that is not a choice reads as the default, as the formatter does
                    Picker("Time format", selection: Binding(
                        get: { TimeStyle(rawValue: timeStyle) ?? .relative }, set: { timeStyle = $0.rawValue }
                    )) {
                        Text("Relative").tag(TimeStyle.relative)
                        Text("Clock").tag(TimeStyle.clock)
                    }
                    .labelsHidden().fixedSize()
                }
                SettingsTabRow(title: "Clock", detail: "How clock times count the hours") {
                    Picker("Clock", selection: Binding(
                        get: { ClockHours(rawValue: clockHours) ?? .system }, set: { clockHours = $0.rawValue }
                    )) {
                        Text("System").tag(ClockHours.system)
                        Text("12 hours").tag(ClockHours.h12)
                        Text("24 hours").tag(ClockHours.h24)
                    }
                    .labelsHidden().fixedSize()
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

/// The sidebar's grouping and sorts, which its own menus change too (one preference, two controls), and what each session row shows.
struct SidebarTabView: View {
    @AppStorage(SidebarStore.groupByKey) private var groupBy = GroupBy.status
    @AppStorage(SidebarStore.sessionSortKey) private var sessionSort = SessionSort.workspace
    @AppStorage(SidebarStore.archiveSortKey) private var archiveSort = ArchiveSort.dateArchived
    @AppStorage(SidebarStore.showsIconKey) private var showsIcon = true
    @AppStorage(SidebarStore.showsBranchKey) private var showsBranch = true
    @AppStorage(SidebarStore.showsProvidersKey) private var showsProviders = true
    @AppStorage(SidebarStore.showsAgeKey) private var showsAge = true

    /// A session of the preview: it has a branch, two providers and an age, so each switch has something to hide.
    private static let sample = SessionRow(
        id: "preview", title: "Fix the flaky login test", workspace: "carrier", agent: "claude", state: .idle,
        updatedAt: Date(timeIntervalSinceNow: -11 * 60), branch: "fix/login-flake", folder: "/preview", providers: ["claude", "codex"]
    )

    var body: some View {
        SettingsPageBody(reset: { AppPreferences().reset(.sidebar) }, preview: {
            SettingsGroup(title: "Preview") {
                SessionRowView(row: Self.sample, showsWorkspace: true).allowsHitTesting(false).padding(.vertical, 6)
            }
        }, content: {
            SettingsGroup(title: "Order") {
                SettingsTabRow(title: "Group epics by", detail: "How the epics under Carrier are grouped", first: true) {
                    picker("Group epics by", selection: $groupBy, options: GroupBy.allCases) { $0.title }
                }
                SettingsTabRow(title: "Sort sessions", detail: "How the Sessions list is grouped and ordered") {
                    picker("Sort sessions", selection: $sessionSort, options: SessionSort.allCases) { $0.title }
                }
                SettingsTabRow(title: "Sort the Archive", detail: "How the archived sessions are ordered") {
                    picker("Sort the Archive", selection: $archiveSort, options: ArchiveSort.allCases) { $0.title }
                }
            }
            SettingsGroup(title: "Session rows") {
                SettingsTabRow(title: "Project icon", detail: "The colored square with the project's initials", first: true) {
                    Toggle("Project icon", isOn: $showsIcon).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(title: "Branch", detail: "Where the session works, the branch or the base folder") {
                    Toggle("Branch", isOn: $showsBranch).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(title: "Providers", detail: "The marks of the providers the session used") {
                    Toggle("Providers", isOn: $showsProviders).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(title: "Age", detail: "How long ago the session was last active") {
                    Toggle("Age", isOn: $showsAge).labelsHidden().toggleStyle(.switch)
                }
            }
        })
    }

    private func picker<Value: Hashable>(_ name: String, selection: Binding<Value>, options: [Value], title: @escaping (Value) -> String) -> some View {
        Picker(name, selection: selection) { ForEach(options, id: \.self) { Text(title($0)).tag($0) } }.labelsHidden().fixedSize()
    }
}

/// How the message box behaves: the key that sends and what the system does to the text. The conversation's own block comes with its slice.
struct ChatTabView: View {
    @AppStorage(AppPreferences.sendKeyKey) private var sendKey = AppPreferences.defaultSendKey
    @AppStorage(AppPreferences.writingToolsKey) private var writingTools = AppPreferences.defaultWritingTools
    @AppStorage(AppPreferences.checksSpellingKey) private var checksSpelling = AppPreferences.defaultChecksSpelling
    @AppStorage(AppPreferences.correctsSpellingKey) private var correctsSpelling = AppPreferences.defaultCorrectsSpelling

    var body: some View {
        SettingsPageBody(reset: { AppPreferences().reset(.chat) }) {
            SettingsGroup(title: "Message box") {
                SettingsTabRow(title: "Send with", detail: "The other key makes a new line", first: true) {
                    Picker("Send with", selection: $sendKey) {
                        Text("Return").tag(SendKey.return)
                        Text("\u{2318}Return").tag(SendKey.commandReturn)
                    }
                    .labelsHidden().fixedSize()
                }
                SettingsTabRow(title: "Writing Tools", detail: "The system's offer to rewrite or proofread what you select") {
                    Toggle("Writing Tools", isOn: $writingTools).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(title: "Check spelling", detail: "Underline words that look misspelled") {
                    Toggle("Check spelling", isOn: $checksSpelling).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(title: "Correct spelling automatically", detail: "Fix a misspelled word as you type it") {
                    Toggle("Correct spelling automatically", isOn: $correctsSpelling).labelsHidden().toggleStyle(.switch)
                }
            }
        }
    }
}

struct NotificationsTabView: View {
    @AppStorage(notifyNeedsYouKey) private var needsYou = true
    @AppStorage(notifyReadyForTestKey) private var readyForTest = true
    @AppStorage(notifyProblemKey) private var problem = false
    @AppStorage(notifyChatNeedsAttentionKey) private var chatNeedsAttention = true
    @AppStorage(notifyChatDoneKey) private var chatDone = false
    @AppStorage(notifyOnlyWhenAwayKey) private var onlyWhenAway = true
    @AppStorage(notifySoundKey) private var sound = true
    @State private var permission: NotificationPermission?
    @State private var testAdvice: String?

    var body: some View {
        SettingsPageBody {
            SettingsGroup(title: "Carrier") {
                SettingsTabRow(title: "Needs attention", detail: "An epic stopped and waits for a person", first: true) {
                    Toggle("Needs attention", isOn: $needsYou).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(title: "Ready for test", detail: "An epic finished and has a PR to try") {
                    Toggle("Ready for test", isOn: $readyForTest).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(title: "A problem", detail: "GitHub refuses a repo, or Carrier stops by itself") {
                    Toggle("A problem", isOn: $problem).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsGroup(title: "Chat") {
                SettingsTabRow(title: "Needs attention", detail: "A session waits for an approval", first: true) {
                    Toggle("Chat needs attention", isOn: $chatNeedsAttention).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(title: "Done", detail: "A session finished its turn") {
                    Toggle("Chat done", isOn: $chatDone).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsGroup(title: "When") {
                SettingsTabRow(title: "Only when Carrier is not in front", detail: "No banner while its window is the one you are looking at", first: true) {
                    Toggle("Only when Carrier is not in front", isOn: $onlyWhenAway).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsGroup(title: "Sound") {
                SettingsTabRow(title: "Play a sound", detail: "A banner plays the notification sound", first: true) {
                    Toggle("Play a sound", isOn: $sound).labelsHidden().toggleStyle(.switch)
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
