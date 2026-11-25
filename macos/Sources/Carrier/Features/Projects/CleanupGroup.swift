import CarrierCore
import SwiftUI

/// The Cleanup group of the page: the switch, the server and its models, the prompt and the Try it box. With Dictation off the group is drawn at 40%; with the
/// switch off only the switch shows, and the rest comes with it.
struct CleanupGroup: View {
    var cleanup = CleanupController.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // the choices are the controller's to read and write; these make the group redraw when they change, Reset included
    @AppStorage(Preference.dictationCleanupEnabled) private var savedEnabled
    @AppStorage(Preference.dictationCleanupServer) private var savedServer
    @AppStorage(Preference.dictationCleanupModel) private var savedModel
    @AppStorage(Preference.dictationCleanupPrompt) private var savedPrompt

    var body: some View {
        SettingsGroup(
            id: "cleanup", title: "Cleanup",
            footer: cleanup.enabled
                ? "In a message box and in the widget the raw text is used when the server is down, the model is missing or it does not answer in 30 seconds."
                : "The server, the model, the prompt and the test appear when it is on."
        ) {
            SettingsTabRow(
                id: "clean-the-text-with-a-model", title: "Clean the text with a model",
                detail: cleanup.enabled && cleanup.canBeOn == false ? "Choose a server and a model below; until then the text stays as dictated" : "After you dictate, a model on this Mac rewrites the text with your prompt",
                first: true
            ) {
                Toggle("Clean the text with a model", isOn: Binding(get: { cleanup.enabled }, set: { cleanup.setEnabled($0) }))
                    .labelsHidden().toggleStyle(.switch)
            }
            // the switch is the whole group's: off, there is nothing else to set, so nothing else is drawn
            // a search for Server, Model, Prompt or Try it with the switch off opens this screen, which is the switch alone: it shows, with nothing to scroll to
            if cleanup.enabled { serverRow; modelRow; promptRow; tryRow }
        }
        .task(id: savedServer) { await cleanup.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Task { await cleanup.refresh() } }
        .onChange(of: cleanup.test) { _, test in
            // the result appears under the button, where VoiceOver is not looking
            switch test {
            case .done(let result): AccessibilityNotification.Announcement("Cleaned in \(String(format: "%.1f", result.seconds)) seconds: \(result.text)").post()
            case .failed(let failure): AccessibilityNotification.Announcement("Could not clean: \(failure.message)").post()
            default: break
            }
        }
    }

    private var serverRow: some View {
        SettingsTabRow(id: "server", title: "Server", detail: "Runs on this Mac; nothing leaves it") {
            HStack(spacing: Tokens.Space.s8) {
                switch cleanup.serverState {
                case .running: StatusChip(text: "Running", tint: .green)
                case .notRunning: StatusChip(text: "Not running", tint: .orange)
                case .unknown: EmptyView()
                }
                ChoicePopUp(
                    label: "Server",
                    options: [(value: "", title: "Choose…")] + CleanupServer.allCases.map { (value: $0.rawValue, title: $0.title) },
                    selection: Binding(get: { cleanup.server?.rawValue ?? "" }, set: { cleanup.choose(server: CleanupServer(rawValue: $0)) })
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
        return SettingsTabRow(id: "model", title: "Model", detail: detail) {
            ChoicePopUp(
                label: "Model", options: [(value: "", title: "Choose…")] + (kept + listed).map { (value: $0, title: $0) },
                selection: Binding(get: { cleanup.model ?? "" }, set: { cleanup.choose(model: $0.isEmpty ? nil : $0) })
            )
            .disabled(cleanup.server == nil)
        }
    }

    private var promptRow: some View {
        SettingsStackedRow(id: "prompt", title: "Prompt", detail: "What you ask the model to do with every dictation: drop filler words, translate, make it technical…") {
            TextEditor(text: Binding(get: { cleanup.prompt }, set: { cleanup.set(prompt: $0) }))
                .font(.scaled(13)).scrollContentBackground(.hidden).frame(height: 96).settingsField()
                .writingToolsBehavior(.disabled).accessibilityLabel("Cleanup prompt")
        }
    }

    /// The test: the sample the model gets, then what it gives back, each under its own label, so it is plain which text is cleaned and what came out.
    private var tryRow: some View {
        SettingsStackedRow(id: "try-it", title: "Try it", detail: "Runs the prompt above on this sample dictation, as the model will get it") {
            VStack(alignment: .leading, spacing: Tokens.Space.s20) {
                testPanel("Dictated", text: cleanupSample, tint: .secondary)
                HStack {
                    Spacer()
                    Button { Task { await cleanup.runTest() } } label: { Label("Clean this sample", icon: .arrowDown) }
                        .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small).disabled(cleanup.test == .running)
                    Spacer()
                }
                testOutput
            }
        }
    }

    /// A labelled box of text: a sample or an answer.
    private func testPanel(_ label: String, text: String, tint: Color, seconds: TimeInterval? = nil) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s6) {
            HStack {
                Text(label).sectionLabel()
                Spacer()
                if let seconds { Text(String(format: "%.1f s", seconds)).font(.scaled(11)).foregroundStyle(.secondary).monospacedDigit() }
            }
            Text(text).font(.scaled(13)).foregroundStyle(tint).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Tokens.Space.s12)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.control, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    @ViewBuilder private var testOutput: some View {
        switch cleanup.test {
        case .idle:
            testPlaceholder("Cleaned", "The result appears here. If the model fails or is slow, the raw text is used and the widget says so.")
        case .running: testWorking
        case .done(let result):
            testPanel("Cleaned", text: result.text, tint: .primary, seconds: result.seconds)
        case .failed(let failure): testFailure(failure.message)
        }
    }

    /// The box of the answer while the model works: a spinner and two lines that shimmer where the text will be.
    private var testWorking: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s10) {
            HStack(spacing: Tokens.Space.s6) {
                Text("Cleaned").sectionLabel()
                Spacer()
                ProgressView().controlSize(.mini)
                Text("Cleaning…").font(.scaled(11)).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: Tokens.Space.s8) {
                RoundedRectangle(cornerRadius: Tokens.Radius.tiny).fill(Color.primary.opacity(0.14)).frame(height: 9)
                RoundedRectangle(cornerRadius: Tokens.Radius.tiny).fill(Color.primary.opacity(0.14)).frame(height: 9).padding(.trailing, Tokens.Space.s90)
            }
            .modifier(Shimmer(active: reduceMotion == false))
            .accessibilityHidden(true)
        }
        .padding(Tokens.Space.s12)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.control, style: .continuous).fill(Color.primary.opacity(0.05)))
        .accessibilityElement(children: .combine)
    }

    /// The box of the answer when the model gave none: the same box in orange, with the cause as a sentence.
    private func testFailure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s6) {
            Label("Could not clean", icon: .warningFilled).sectionLabel().foregroundStyle(.orange)
            Text(message).font(.scaled(13)).foregroundStyle(.primary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(Tokens.Space.s12)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.control, style: .continuous).fill(Color.orange.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.control, style: .continuous).strokeBorder(Color.orange.opacity(0.4), lineWidth: 1))
    }

    private func testPlaceholder(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s6) {
            Text(label).sectionLabel()
            Text(text).font(.scaled(12)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(Tokens.Space.s12)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.control, style: .continuous).strokeBorder(Color.primary.opacity(0.1), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }
}
