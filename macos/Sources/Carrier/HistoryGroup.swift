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
        .onChange(of: days) { dictation.records.deleteOldAudio() }
        .confirmationDialog("Delete all the audio?", isPresented: $confirmingDelete) {
            Button("Delete all audio", role: .destructive) { dictation.records.deleteAllAudio() }
        } message: {
            Text("The transcripts stay.")
        }
        HistoryList(records: dictation.records)
    }
}

/// The entries: a search over the text and the destination and a filter by outcome, then a group a day with the newest first. A row opens to its detail,
/// copies its text and deletes its entry.
struct HistoryList: View {
    let records: DictationRecords
    @State private var query = ""
    @State private var outcome: DictationOutcome?
    @State private var open: UUID?

    var body: some View {
        let _ = Signposts.render.emitEvent("history body", "\(records.entries.count) entries")
        let shown = dictationEntries(records.entries, matching: query, outcome: outcome)
        SettingsGroup(title: "") {
            TextField("", text: $query, prompt: Text("Search your dictations")).accessibilityLabel("Search your dictations").settingsField(icon: .search)
            HStack(spacing: 6) {
                FilterChip(title: "All", on: outcome == nil) { outcome = nil }
                ForEach(DictationOutcome.allCases, id: \.self) { choice in
                    FilterChip(title: choice.title, on: outcome == choice) { outcome = choice }
                }
            }
            .padding(.vertical, 4)
        }
        if shown.isEmpty {
            SettingsGroup(title: "") {
                EmptyStateView(
                    icon: records.entries.isEmpty ? "waveform" : "magnifyingglass", title: records.entries.isEmpty ? "No dictations yet" : "Nothing matches",
                    line: records.entries.isEmpty ? "What you dictate shows up here." : "Try another word or filter."
                )
                .frame(minHeight: 220)
            }
        } else {
            ForEach(dictationDays(shown)) { day in
                SettingsGroup(title: dictationDayTitle(day.day, now: Date())) {
                    ForEach(day.entries) { entry in
                        HistoryRow(entry: entry, audio: records.audioURL(of: entry.id), open: open == entry.id, toggle: { open = open == entry.id ? nil : entry.id }, delete: { records.delete(entry.id) })
                    }
                }
            }
            SettingsGroup(title: "") {
                Text("\(shown.count) of \(records.entries.count) dictations").font(.scaled(11)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
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

    private var tint: Color {
        switch entry.outcome {
        case .pasted: .green
        case .copied: Color.themeAccent
        case .cancelled: .secondary
        case .failed: .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Button(action: toggle) {
                    HStack(alignment: .top, spacing: 10) {
                        Text(entry.started.formatted(date: .omitted, time: .shortened)).font(.scaled(11)).monospacedDigit().foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
                        Text(entry.shown).lineLimit(open ? nil : 2).italic(entry.outcome == .cancelled)
                            .foregroundStyle(entry.outcome == .cancelled ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityValue(open ? "Expanded" : "Collapsed").accessibilityHint("Shows the details")
                IconButton(icon: copied ? "checkmark" : "doc.on.doc", name: copied ? "Copied" : "Copy text") { copy(entry.shown) }
                IconButton(icon: .trash, name: "Delete dictation") { confirmingDelete = true }
            }
            FlowLayout(spacing: 6) {
                StatusChip(text: entry.outcome.title, tint: tint)
                chip(entry.destination)
                chip(entry.model)
                chip("transcribed in \(seconds(entry.transcription))")
                chip("\(entry.words) \(entry.words == 1 ? "word" : "words") · \(seconds(entry.audio))")
                if entry.cleaned != nil { StatusChip(text: "cleaned", tint: .themeAccent) }
            }
            .padding(.leading, 74)
            if open { detail.padding(.leading, 74) }
        }
        .padding(.vertical, 9)
        .confirmationDialog("Delete this dictation?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive, action: delete)
        } message: {
            Text("Its text and its audio are deleted. The statistics stay as they are.")
        }
    }

    private var detail: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
            if let cleaned = entry.cleaned {
                GridRow { field("Cleaned text", cleaned).gridCellColumns(2) }
                GridRow { field("As recognized", entry.text).gridCellColumns(2) }
            } else {
                GridRow { field("Text", entry.text).gridCellColumns(2) }
            }
            GridRow {
                field("Speech model", entry.model)
                field("Transcription", "\(seconds(entry.transcription)) for \(seconds(entry.audio)) of audio")
            }
            GridRow {
                field("Cleanup", entry.cleanupModel.map { "\($0) · \(seconds(entry.cleanupSeconds ?? 0))" } ?? "Not used")
                field("Went to", entry.destination)
            }
            if let audio {
                GridRow {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Audio").sectionLabel()
                        AudioPlayerView(url: audio)
                    }
                    .gridCellColumns(2)
                }
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
    }

    private func field(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).sectionLabel()
            Text(value).font(.scaled(12)).textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chip(_ text: String) -> some View { StatusChip(text: text, tint: .secondary) }

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
