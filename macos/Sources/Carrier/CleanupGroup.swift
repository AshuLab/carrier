import CarrierCore
import SwiftUI

/// The Cleanup group of the page: the switch, the server and its models, the prompt and the Test. With Dictation off the group is drawn at 40%.
struct CleanupGroup: View {
    var cleanup = CleanupController.shared
    // the choices are the controller's to read and write; these make the group redraw when they change, Reset included
    @AppStorage(AppPreferences.dictationCleanupEnabledKey) private var savedEnabled = false
    @AppStorage(AppPreferences.dictationCleanupServerKey) private var savedServer: String?
    @AppStorage(AppPreferences.dictationCleanupModelKey) private var savedModel: String?
    @AppStorage(AppPreferences.dictationCleanupPromptKey) private var savedPrompt: String?

    var body: some View {
        SettingsGroup(title: "Cleanup") {
            SettingsTabRow(
                title: "Clean the text with a model",
                detail: cleanup.canBeOn ? "After you dictate, a model on this Mac rewrites the text with your prompt" : "Choose a server and a model first", first: true
            ) {
                Toggle("Clean the text with a model", isOn: Binding(get: { cleanup.enabled }, set: { cleanup.setEnabled($0) }))
                    .labelsHidden().toggleStyle(.switch).disabled(cleanup.canBeOn == false)
            }
            serverRow
            modelRow
            promptRow
        }
        .task(id: savedServer) { await cleanup.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Task { await cleanup.refresh() } }
        .onChange(of: cleanup.test) { _, test in
            // the result appears under the button, where VoiceOver is not looking
            if case .done(let result) = test { AccessibilityNotification.Announcement("Cleaned in \(String(format: "%.1f", result.seconds)) seconds: \(result.text)").post() }
        }
    }

    private var serverRow: some View {
        SettingsTabRow(title: "Server", detail: "Runs on this Mac; nothing leaves it") {
            HStack(spacing: 8) {
                switch cleanup.serverState {
                case .running: StatusChip(text: "Running", tint: .green)
                case .notRunning: StatusChip(text: "Not running", tint: .orange)
                case .unknown: EmptyView()
                }
                ChoicePopUp(
                    label: "Server",
                    options: [(value: "", title: "Choose…")] + CleanupServer.allCases.map { (value: $0.rawValue, title: $0.title) },
                    selection: Binding(get: { cleanup.server?.rawValue ?? "" }, set: { cleanup.choose(server: CleanupServer(rawValue: $0)) }), width: 160
                )
            }
        }
    }

    private var modelRow: some View {
        var listed: [String] = []
        if case .running(let models) = cleanup.serverState { listed = models }
        // the saved model stays on the list when the server is down or no longer lists it, so the popup still shows what is chosen
        let kept = cleanup.model.flatMap { listed.contains($0) ? nil : [$0] } ?? []
        let detail = cleanup.server == nil ? "Choose a server first" : cleanup.serverState == .notRunning ? "Start the server to see its models" : "Small models are faster; the paste waits for it"
        return SettingsTabRow(title: "Model", detail: detail) {
            ChoicePopUp(
                label: "Model", options: [(value: "", title: "Choose…")] + (kept + listed).map { (value: $0, title: $0) },
                selection: Binding(get: { cleanup.model ?? "" }, set: { cleanup.choose(model: $0.isEmpty ? nil : $0) }), width: 200
            )
            .disabled(cleanup.server == nil)
        }
    }

    private var promptRow: some View {
        SettingsStackedRow(title: "Prompt", detail: "What you ask the model to do with every dictation: drop filler words, translate, make it technical…") {
            TextEditor(text: Binding(get: { cleanup.prompt }, set: { cleanup.set(prompt: $0) }))
                .font(.scaled(13)).scrollContentBackground(.hidden).frame(height: 96).settingsField()
                .writingToolsBehavior(.disabled).accessibilityLabel("Cleanup prompt")
            HStack(spacing: 10) {
                Button { Task { await cleanup.runTest() } } label: { Label("Test with a sample", systemImage: "play") }
                    .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small).disabled(cleanup.test == .running)
                testResult
            }
        }
    }

    @ViewBuilder private var testResult: some View {
        switch cleanup.test {
        case .idle: Text("If the model fails or is slow, the raw text is used and the widget says so.").font(.scaled(11)).foregroundStyle(.secondary)
        case .running: Text("Cleaning…").font(.scaled(11)).foregroundStyle(.secondary)
        case .done(let result):
            Text("\(Text("“\(result.text)”").foregroundStyle(.primary)) · \(String(format: "%.1f", result.seconds)) s").font(.scaled(11)).foregroundStyle(.secondary)
        case .failed(let failure): ProblemLine(text: failure.message, font: .scaled(11))
        }
    }
}
