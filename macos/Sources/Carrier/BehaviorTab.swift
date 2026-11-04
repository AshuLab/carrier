import AppKit
import CarrierCore
import SwiftUI

/// The Behavior tab: the values of `config.json` the engine reads when it starts (CarrierCore/EngineConfig.swift), in four
/// groups. Every change that the engine would accept is written to the file as it is made, in place; nothing restarts Carrier,
/// which reads the file when it starts. "Reset to defaults" is the one button.
struct BehaviorTabView: View {
    @ObservedObject private var start = StartController.shared
    @State private var saved = EngineConfig()
    @State private var draft = EngineConfig()
    /// fields whose text is not a number yet
    @State private var unparsable: Set<String> = []
    @State private var unreadable = false
    @State private var failure: String?
    @State private var note: String?

    private var path: String { configFilePath() }

    private var problems: [String: String] {
        draft.problems.merging(unparsable.map { ($0, "Must be a number") }) { _, text in text }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if unreadable {
                Label("The engine is not configured: config.json in the Carrier folder is missing or is not a JSON object.", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
            }
            group("Rhythm") {
                row("Check GitHub every", "Minutes between looks for ready epics", "pollIntervalMinutes", first: true) {
                    field("pollIntervalMinutes", $draft.pollIntervalMinutes, unit: "min", parse: { Double($0.replacingOccurrences(of: ",", with: ".")) }, format: shownNumber, step: { $0 + Double($1) > 0 ? $0 + Double($1) : nil })
                }
                row("Log level", "How much Carrier writes to its log", "logLevel") {
                    Picker("Log level", selection: $draft.logLevel) { ForEach(EngineConfig.logLevels, id: \.self) { Text($0) } }
                        .labelsHidden().frame(width: 90)
                }
            }
            group("Finished epics") {
                row("Keep in view for", "Days a merged or cancelled epic stays listed, 1 to 30", "finishedWindowDays", first: true) { integer("finishedWindowDays", $draft.finishedWindowDays, min: 1, unit: "days") }
            }
            group("Capacity") {
                row("Epics at once", "Epics running at the same time", "maxConcurrentEpics", first: true) { integer("maxConcurrentEpics", $draft.maxConcurrentEpics, min: 1) }
                row("Review rounds", "Rounds before the epic goes to needs-human", "maxReviews") { integer("maxReviews", $draft.maxReviews, min: 1) }
            }
            group("Agent runs") {
                row("Retries", "After a technical failure of an agent run", "maxExecutionRetries", first: true) { integer("maxExecutionRetries", $draft.maxExecutionRetries, min: 0) }
                row("Time per agent run", "Limit of one agent run", "maxExecutionHours") {
                    HStack(spacing: 10) {
                        if draft.maxExecutionHours != nil {
                            integer("maxExecutionHours", Binding(get: { draft.maxExecutionHours ?? 4 }, set: { draft.maxExecutionHours = $0 }), min: 1, unit: "h")
                        }
                        Picker("Time per agent run", selection: Binding(get: { draft.maxExecutionHours == nil }, set: { unlimited in
                            unparsable.remove("maxExecutionHours")
                            draft.maxExecutionHours = unlimited ? nil : 4
                        })) {
                            Text("Limit").tag(false)
                            Text("Unlimited").tag(true)
                        }.pickerStyle(.segmented).labelsHidden().fixedSize()
                    }
                }
                row("GitHub call timeout", "Each short call to GitHub", "githubCallTimeoutSeconds") { integer("githubCallTimeoutSeconds", $draft.githubCallTimeoutSeconds, min: 1, unit: "s") }
            }
            HStack(spacing: 8) {
                if let failure {
                    Label(failure, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange)
                } else if let note {
                    Label(note, systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(.green)
                } else {
                    Text("Saved as you change them. Carrier reads these when it starts.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("Reset to defaults") { draft = EngineConfig(); unparsable = [] }.disabled(draft == EngineConfig() && unparsable.isEmpty)
            }
            .padding(.horizontal, 4)
        }
        .buttonStyle(.glass).buttonBorderShape(.capsule)
        // nothing to edit until the file reads; it is read again when it appears or goes (`StartController` checks every 3 seconds)
        .disabled(unreadable)
        .onAppear(perform: load)
        .onChange(of: start.configExists) { load() }
        // a file that is there but unreadable may be fixed in another app: look again when Carrier is back in front (only then, so no edit is lost)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in if unreadable { load() } }
        .onChange(of: draft) {
            note = nil
            autosave()
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        SettingsGroup(title: title) { content() }
    }

    private func row<Control: View>(_ title: String, _ detail: String, _ key: String, first: Bool = false, @ViewBuilder control: () -> Control) -> some View {
        SettingsTabRow(title: title, detail: problems[key] ?? detail, first: first) { control() }
            .foregroundStyle(problems[key] == nil ? Color.primary : Color.orange)
    }

    private func integer(_ key: String, _ value: Binding<Int>, min: Int, unit: String? = nil) -> some View {
        field(key, value, unit: unit, parse: { Int($0) }, format: { String($0) }, step: { $0 + $1 >= min ? $0 + $1 : nil })
    }

    private func field<Value: Equatable>(_ key: String, _ value: Binding<Value>, unit: String?, parse: @escaping (String) -> Value?, format: @escaping (Value) -> String, step: @escaping (Value, Int) -> Value?) -> some View {
        HStack(spacing: 6) {
            NumberField(key: key, value: value, unparsable: $unparsable, invalid: problems[key] != nil, parse: parse, format: format, step: step)
            if let unit { Text(unit).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func shownNumber(_ value: Double) -> String { value == value.rounded() ? String(Int(value)) : String(value) }

    private func load() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else {
            unreadable = true
            note = nil
            failure = nil
            unparsable = []
            return
        }
        unreadable = false
        saved = EngineConfig(json: data)
        draft = saved
    }

    /// Writes the file; false (with the reason shown) when it could not.
    private func write() -> Bool {
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url), let updated = draft.applied(to: data) else {
            failure = "The config file could not be read or the values are not valid."
            return false
        }
        do {
            try updated.write(to: url, options: .atomic)
            failure = nil
            saved = draft
            return true
        } catch {
            FileHandle.standardError.write(Data("carrier: saving \(url.path) failed: \(error)\n".utf8))
            failure = "Could not save the config file: \(error.localizedDescription)"
            return false
        }
    }

    /// Writes what the person just changed, when the engine would accept it; a value that is still being typed waits.
    private func autosave() {
        guard unreadable == false, draft != saved, problems.isEmpty else { return }
        if write() { note = "Saved" }
    }
}

/// The green line after a save.
struct SavedNote: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "checkmark.circle.fill").fontWeight(.medium).foregroundStyle(.green)
            .padding(.horizontal, 14).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.green.opacity(0.13)))
    }
}

/// A question under the tab's content with a way out and a red button: the restart that interrupts epics.
struct ConfirmationCard: View {
    let text: String
    let confirm: String
    let cancel: () -> Void
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                Button(confirm, role: .destructive, action: action)
            }
            .buttonStyle(.glass).buttonBorderShape(.capsule)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.12)))
    }
}

/// A text field that hands its number to `value` as it is typed, so Save is on at once; text that is not a number yet is
/// reported through `unparsable` and the value keeps its last good number.
private struct NumberField<Value: Equatable>: View {
    let key: String
    @Binding var value: Value
    @Binding var unparsable: Set<String>
    let invalid: Bool
    let parse: (String) -> Value?
    let format: (Value) -> String
    /// The value one click of − (-1) or + (1) moves to; nil when it would go below the least the engine takes.
    let step: (Value, Int) -> Value?
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 0) {
            stepButton("minus", -1)
            TextField("", text: $text).textFieldStyle(.plain).multilineTextAlignment(.center).frame(width: 42).focused($focused)
            stepButton("plus", 1)
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.secondary.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(invalid ? Color.red : focused ? Color.accentColor : Color.clear, lineWidth: 1.5))
            .onAppear { text = format(value) }
            .onChange(of: text) {
                if let parsed = parse(text) {
                    unparsable.remove(key)
                    if parsed != value { value = parsed }
                } else {
                    unparsable.insert(key)
                }
            }
            // Revert, or a reload: show the value the draft now has, unless the text already means it
            .onChange(of: value) { if parse(text) != value { text = format(value) } }
            // Revert clears the mark: text that is still not a number goes back to the value
            .onChange(of: unparsable) { if unparsable.contains(key) == false, parse(text) == nil { text = format(value) } }
            .accessibilityLabel(key)
    }

    private func stepButton(_ symbol: String, _ direction: Int) -> some View {
        Button {
            guard let next = step(parse(text) ?? value, direction) else { return }
            unparsable.remove(key)
            value = next
            text = format(next)
        } label: {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel(direction < 0 ? "Less" : "More")
    }
}

/// The main button of a tab's footer: a flat accent capsule, grey when it cannot be pressed.
struct PrimaryCapsuleButtonStyle: ButtonStyle {
    /// The one button a screen is about (Start Carrier), bigger than a footer's.
    var large = false

    func makeBody(configuration: Configuration) -> some View { Face(configuration: configuration, large: large) }

    private struct Face: View {
        let configuration: ButtonStyleConfiguration
        let large: Bool
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            configuration.label.fontWeight(.semibold).font(large ? .title3.weight(.semibold) : .body.weight(.semibold))
                .foregroundStyle(enabled ? Color.white : Color.secondary)
                .padding(.horizontal, large ? 24 : 16).padding(.vertical, large ? 9 : 6)
                .background(Capsule().fill(enabled ? Color.accentColor : Color.secondary.opacity(0.18)))
                .shadow(color: .black.opacity(enabled ? 0.3 : 0), radius: 1, y: 1)
                .opacity(configuration.isPressed ? 0.8 : 1)
        }
    }
}
