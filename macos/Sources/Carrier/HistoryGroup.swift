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
                ChoicePopUp(label: "Delete audio older than", options: dictationAudioLimits.map { (value: $0.days, title: $0.title) }, selection: $days, width: 110)
            }
            SettingsTabRow(title: "Audio on disk", detail: formatAudioOnDisk(bytes: dictation.records.audioBytes, files: dictation.records.audioIDs.count)) {
                Button("Delete all audio", role: .destructive) { confirmingDelete = true }
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

/// The entries, grouped by day with the newest first, with a search over the text and the destination and a filter by outcome. A row opens to its
/// detail, copies its text and deletes its entry.
struct HistoryList: View {
    let records: DictationRecords
    @State private var query = ""
    @State private var outcome: DictationOutcome?
    @State private var open: UUID?

    var body: some View {
        let shown = dictationEntries(records.entries, matching: query, outcome: outcome)
        VStack(alignment: .leading, spacing: 10) {
            TextField("Search your dictations", text: $query).settingsField(icon: "magnifyingglass")
            HStack(spacing: 6) {
                FilterChip(title: "All", on: outcome == nil) { outcome = nil }
                ForEach(DictationOutcome.allCases, id: \.self) { choice in
                    FilterChip(title: choice.title, on: outcome == choice) { outcome = choice }
                }
            }
            if shown.isEmpty {
                VStack(spacing: 4) {
                    Text(records.entries.isEmpty ? "No dictations yet" : "Nothing matches").fontWeight(.medium)
                    Text(records.entries.isEmpty ? "What you dictate shows up here." : "Try another word or filter.").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 36)
            } else {
                ForEach(dictationDays(shown)) { day in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(dictationDayTitle(day.day, now: Date())).sectionLabel().padding(.leading, 14).padding(.top, 8)
                        SettingsTabCard {
                            ForEach(Array(day.entries.enumerated()), id: \.element.id) { index, entry in
                                if index > 0 { SettingsDivider() }
                                HistoryRow(entry: entry, audio: records.audioURL(of: entry.id), open: open == entry.id, toggle: { open = open == entry.id ? nil : entry.id }, delete: { records.delete(entry.id) })
                            }
                        }
                    }
                }
                Text("\(shown.count) of \(records.entries.count) dictations").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
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
                        Text(entry.started.formatted(date: .omitted, time: .shortened)).font(.caption).monospacedDigit().foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
                        Text(entry.shown).lineLimit(open ? nil : 2).italic(entry.outcome == .cancelled)
                            .foregroundStyle(entry.outcome == .cancelled ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityValue(open ? "Expanded" : "Collapsed").accessibilityHint("Shows the details")
                Button { copy(entry.shown) } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless).help("Copy text").accessibilityLabel("Copy text")
                Button(action: delete) { Image(systemName: "trash") }
                    .buttonStyle(.borderless).help("Delete").accessibilityLabel("Delete dictation")
            }
            HStack(spacing: 6) {
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
            Text(value).font(.callout).textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chip(_ text: String) -> some View { StatusChip(text: text, tint: .secondary) }

    private func seconds(_ value: Double) -> String { value < 10 ? String(format: "%.1f s", value) : "\(Int(value.rounded())) s" }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
