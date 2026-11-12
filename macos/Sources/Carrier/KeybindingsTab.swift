import AppKit
import CarrierCore
import SwiftUI

/// The shortcuts by group: click one and press the new keys (Esc cancels, Delete clears it); a combination another action has is flagged
/// with that action's title, and one the system keeps for editing and the app is refused.
struct KeybindingsTabView: View {
    /// Counts the changes made here: the table is read from the preferences, and this makes the page draw again.
    @State private var revision = 0
    @State private var recording: ShortcutCommand?
    @State private var monitor: Any?
    /// The combination the last try was refused for, and the action it was for.
    @State private var refused: (command: ShortcutCommand, combo: KeyCombo)?

    var body: some View {
        let _ = revision
        let table = ShortcutTable()
        SettingsPageBody(reset: { AppPreferences().reset(.keybindings); revision += 1 }) {
            ForEach(ShortcutGroup.allCases, id: \.self) { group in
                SettingsGroup(title: group.rawValue) {
                    ForEach(ShortcutCommand.allCases.filter { $0.group == group }, id: \.self) { command in
                        row(command, table: table, first: command == ShortcutCommand.allCases.first { $0.group == group })
                    }
                }
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private func row(_ command: ShortcutCommand, table: ShortcutTable, first: Bool) -> some View {
        let combo = table.combo(for: command)
        let clash = combo.flatMap { table.clash(of: $0, for: command) }
        let text = recording == command ? "Press the keys…" : combo?.text ?? "None"
        return SettingsTabRow(title: command.title, detail: "Default: \(command.defaultCombo?.text ?? "none")", first: first) {
            HStack(spacing: 8) {
                if let refused, refused.command == command {
                    Label("\(refused.combo.text) is the system's", systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                } else if let clash {
                    Label("Also \(clash.title)", systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                }
                if table.isDefault(command) == false {
                    Button { table.set(command.defaultCombo, for: command); revision += 1 } label: {
                        Label("Default", systemImage: "arrow.counterclockwise").labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(HoverTextButtonStyle(tint: nil)).accessibilityLabel("Back to the default for \(command.title)")
                }
                Button(text) { startRecording(command) }
                    .buttonStyle(KeyCapButtonStyle(recording: recording == command, empty: combo == nil))
                    .accessibilityLabel("Shortcut for \(command.title)").accessibilityValue(combo?.text ?? "None")
            }
        }
    }

    private func startRecording(_ command: ShortcutCommand) {
        stopRecording()
        recording = command
        refused = nil
        // the next key goes here, not to the window's shortcuts: this monitor was added after theirs, and the key is not passed on
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let table = ShortcutTable()
            switch event.keyCode {
            case 53: stopRecording()
            case 51, 117:
                table.set(nil, for: command)
                revision += 1
                stopRecording()
            default:
                if let combo = KeyCombo(key: event.charactersIgnoringModifiers ?? "", modifiers: .init(event.modifierFlags)) {
                    if combo.isReserved {
                        refused = (command, combo)
                        stopRecording()
                        return nil
                    }
                    table.set(combo, for: command)
                    revision += 1
                    stopRecording()
                }
            }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = nil
    }
}

/// The button that shows a shortcut: a key cap, the keys in a monospaced face on a quiet fill; the theme's accent ring and words while it waits for the
/// keys, and the words quieter when there is no shortcut.
private struct KeyCapButtonStyle: ButtonStyle {
    let recording: Bool
    let empty: Bool

    func makeBody(configuration: Configuration) -> some View { Face(configuration: configuration, recording: recording, empty: empty) }

    private struct Face: View {
        let configuration: ButtonStyleConfiguration
        let recording: Bool
        let empty: Bool
        @State private var hovered = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
            configuration.label
                .font(.scaled(12, weight: .semibold, design: .monospaced))
                .foregroundStyle(recording ? Color.themeAccent : empty ? Color.secondary : Color.primary)
                .frame(minWidth: 96).padding(.horizontal, 10).padding(.vertical, 5)
                .background(shape.fill(Color.primary.opacity(configuration.isPressed ? 0.16 : hovered || recording ? 0.12 : 0.08)))
                .overlay { if recording { shape.strokeBorder(Color.themeAccent, lineWidth: 1.5) } }
                .contentShape(shape)
                .onHover { hovered = $0 }
                .animation(.easeOut(duration: 0.12), value: hovered)
                .animation(.easeOut(duration: 0.12), value: recording)
        }
    }
}
