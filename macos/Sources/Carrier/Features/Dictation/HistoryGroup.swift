import CarrierCore
import SwiftUI

/// The History segment of the Dictation page: its settings (Keep the text of my dictations) and the list of what was dictated.
struct HistoryGroup: View {
    var dictation = DictationController.shared
    // the preference is read and written by the switch; this makes the group redraw when Reset changes it
    @AppStorage(AppPreferences.dictationKeepTextKey) private var keep = AppPreferences.defaultDictationKeepText
    @AppStorage(AppPreferences.dictationKeepAudioKey) private var keepAudio = AppPreferences.defaultDictationKeepAudio
    @AppStorage(AppPreferences.dictationDeleteAudioAfterKey) private var days = AppPreferences.defaultDictationDeleteAudioAfter
    @State private var confirmingDelete = false

    var body: some View {
        SettingsGroup(title: "History") {
            SettingsTabRow(
                title: "Keep the text of my dictations",
                detail: "The list below, with search, copy and delete, in plain text on this Mac. Off: nothing new is saved and what is there stays",
                first: true
            ) {
                Toggle("Keep the text of my dictations", isOn: $keep).labelsHidden().toggleStyle(.switch)
            }
            SettingsTabRow(title: "Keep the audio", detail: "Off by default. Each dictation that is recorded then has its audio to play back") {
                Toggle("Keep the audio", isOn: $keepAudio).labelsHidden().toggleStyle(.switch)
            }
            SettingsTabRow(title: "Delete audio older than", detail: "The transcripts stay") {
                ChoicePopUp(label: "Delete audio older than", options: dictationAudioLimits.map { (value: $0.days, title: $0.title) }, selection: $days)
            }
            SettingsTabRow(title: "Audio on disk", detail: formatAudioOnDisk(bytes: dictation.records.audioBytes, files: dictation.records.audioIDs.count)) {
                Button(role: .destructive) { confirmingDelete = true } label: { Label("Delete all audio", icon: .trash) }
                    .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small).disabled(dictation.records.audioIDs.isEmpty)
            }
        }
        .onChange(of: days) { Task { await dictation.records.deleteOldAudio() } }
        .confirmationDialog("Delete all the audio?", isPresented: $confirmingDelete) {
            Button("Delete all audio", role: .destructive) { dictation.records.deleteAllAudio() }
        } message: {
            Text("The transcripts stay.")
        }
        HistoryList(records: dictation.records)
    }
}

/// The entries: a search over the text and the destination and a filter by outcome, then a group a day with the newest first, the first
/// `dictationHistoryPage` and a "Show more" for the rest. A row opens to its detail, copies its text and deletes its entry.
struct HistoryList: View {
    let records: DictationRecords
    @State private var query = ""
    @State private var outcome: DictationOutcome?
    @State private var open: UUID?
    @State private var limit = dictationHistoryPage
    /// What the list draws, worked out when the search, the filter, the entries or `limit` change, not at each `body`.
    @State private var shown: (days: [DictationDay], matched: Int) = ([], 0)
    /// False until the first `refresh`, so the empty states are not drawn for the pass before the list is worked out.
    @State private var ready = false

    private func refresh() {
        shown = dictationHistory(records.entries, matching: query, outcome: outcome, limit: limit)
        ready = records.loaded
    }

    /// A new search or filter starts from the first page; `limit` moving is what refreshes when it was further down.
    private func startOver() {
        if limit == dictationHistoryPage { refresh() } else { limit = dictationHistoryPage }
    }

    var body: some View {
        let _ = Signposts.render.emitEvent("history body", "\(records.entries.count) entries")
        SettingsGroup(title: "") {
            TextField("", text: $query, prompt: Text("Search your dictations")).accessibilityLabel("Search your dictations").settingsField(icon: .search)
            SegmentedChoice(options: [(value: DictationOutcome?.none, title: "All", icon: nil)] + DictationOutcome.allCases.map { (value: Optional($0), title: $0.title, icon: nil) }, selection: $outcome)
                .accessibilityLabel("Outcome")
                .padding(.vertical, 4)
        }
        .onChange(of: query, initial: true) { startOver() }
        .onChange(of: outcome) { startOver() }
        .onChange(of: records.entries) { refresh() }
        .onChange(of: records.loaded) { refresh() }
        .task { await records.load() }
        .onChange(of: limit) { refresh() }
        if ready == false {
            EmptyView()
        } else if shown.matched == 0 {
            SettingsGroup(title: "") {
                EmptyStateView(
                    icon: records.entries.isEmpty ? .waveform : .search, title: records.entries.isEmpty ? "No dictations yet" : "Nothing matches",
                    line: records.entries.isEmpty ? "What you dictate shows up here." : "Try another word or filter."
                )
                .frame(minHeight: 220)
            }
        } else {
            ForEach(shown.days) { day in
                SettingsGroup(title: dictationDayTitle(day.day, now: Date())) {
                    ForEach(day.entries) { entry in
                        HistoryRow(entry: entry, audio: records.audioURL(of: entry.id), open: open == entry.id, toggle: { open = open == entry.id ? nil : entry.id }, delete: { Task { await records.delete(entry.id) } })
                    }
                }
            }
            SettingsGroup(title: "") {
                Text("\(shown.matched) of \(records.entries.count) dictations").font(.scaled(11)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                if shown.matched > limit {
                    Button("Show \(min(dictationHistoryPage, shown.matched - limit)) more") { limit += dictationHistoryPage }
                        .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small).frame(maxWidth: .infinity)
                }
            }
        }
    }
}

private struct HistoryRow: View {
    let entry: DictationEntry
    let audio: URL?
    let open: Bool
    let toggle: () -> Void
    let delete: () -> Void
    @State private var copied = false
    @State private var confirmingDelete = false
    @State private var hovered = false

    private var tint: Color {
        switch entry.outcome {
        case .pasted: .green
        case .copied: Color.themeAccent
        case .cancelled: .secondary
        case .failed: .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Button(action: toggle) {
                    HStack(alignment: .top, spacing: 10) {
                        Text(entry.started.formatted(date: .omitted, time: .shortened)).font(.scaled(11)).monospacedDigit().foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.shown).lineLimit(open ? nil : 2).italic(entry.outcome == .cancelled)
                                .foregroundStyle(entry.outcome == .cancelled ? .secondary : .primary)
                            meta
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityValue(open ? "Expanded" : "Collapsed").accessibilityHint("Shows the details")
                // quiet until the pointer is on the row or it is open; still there for the keyboard and VoiceOver
                HStack(spacing: 2) {
                    IconButton(icon: copied ? .check : .copy, name: copied ? "Copied" : "Copy text") { copy(entry.shown) }
                    IconButton(icon: .trash, name: "Delete dictation") { confirmingDelete = true }
                }
                .opacity(hovered || open || copied || confirmingDelete ? 1 : 0)
            }
            if open { detail.padding(.leading, 74) }
        }
        .padding(.vertical, 10)
        .onHover { hovered = $0 }
        .confirmationDialog("Delete this dictation?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive, action: delete)
        } message: {
            Text("Its text and its audio are deleted. The statistics stay as they are.")
        }
    }

    /// One quiet line under the text: a dot of the outcome's color and its name, then where it went, the words and the length. One `Text`, so it wraps as a sentence.
    private var meta: some View {
        let words = entry.words == 0 ? "" : "\(entry.words) \(entry.words == 1 ? "word" : "words") · "
        let line = Text("\(Image(systemName: "circle.fill"))").font(.scaled(6)).baselineOffset(1).foregroundStyle(tint)
            + Text(" \(entry.outcome.title)").fontWeight(.medium).foregroundStyle(.primary)
            + Text(" · \(entry.destination) · \(words)\(seconds(entry.audio))").foregroundStyle(.secondary)
        return Group {
            if entry.cleaned != nil { line + Text(" · cleaned").foregroundStyle(Color.themeAccent) } else { line }
        }
        .font(.scaled(11.5))
    }

    /// What the line above did not say, with no box of its own: a dashed rule, the text as recognized when cleanup changed it (the row already shows the
    /// text that counts), the model, how long it took, the cleanup, and the audio.
    private var detail: some View {
        VStack(alignment: .leading, spacing: 10) {
            DashedRule().stroke(Color.primary.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [3, 3])).frame(height: 1)
            if entry.cleaned != nil {
                VStack(alignment: .leading, spacing: 1) {
                    Text("As recognized").sectionLabel()
                    Text(entry.text).font(.scaled(12)).foregroundStyle(.secondary).textSelection(.enabled)
                        .padding(.leading, 10).overlay(alignment: .leading) { Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 2) }
                }
            }
            Grid(alignment: .topLeading, horizontalSpacing: 18, verticalSpacing: 8) {
                GridRow {
                    field("Speech model", entry.model)
                    field("Transcription", "\(entry.transcription < 0.05 ? "Instant" : seconds(entry.transcription)) for \(seconds(entry.audio)) of audio")
                    field("Cleanup", entry.cleanupModel.map { "\($0) · \(seconds(entry.cleanupSeconds ?? 0))" } ?? "Not used")
                }
                if let audio {
                    GridRow {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Audio").sectionLabel()
                            AudioPlayerView(url: audio)
                        }
                        .gridCellColumns(3)
                    }
                }
            }
        }
        .padding(.top, 2).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func field(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).sectionLabel()
            Text(value).font(.scaled(12)).textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func seconds(_ value: Double) -> String { value < 10 ? String(format: "%.1f s", value) : "\(Int(value.rounded())) s" }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        AccessibilityNotification.Announcement("Copied").post()
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}

/// A horizontal line, for a dashed rule.
private struct DashedRule: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
