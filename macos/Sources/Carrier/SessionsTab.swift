import CarrierCore
import SwiftUI

/// The Sessions tab: the two ages of the session clock, each a number of days or Never. A change is written to the chat's `chat.json` as
/// it is made (CarrierCore/SessionAges.swift); the chat host reads the file each pass, so nothing is restarted.
struct SessionsTabView: View {
    @State private var saved = SessionAges()
    @State private var draft = SessionAges()
    /// fields whose text is not a number yet
    @State private var unparsable: Set<String> = []
    @State private var failure: String?

    private var problems: [SessionAgeField: String] {
        sessionAgeProblems(draft, unparsable: Set(unparsable.map { $0 == "archive" ? .archive : .delete }))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsGroup(title: "Session clock") {
                row("Archive after", "Days without activity before a session is archived", .archive, off: nil, first: true, age: $draft.archive, fallback: defaultArchiveAfterDays)
                row("Delete after", "Days an archived session waits before it is deleted, with its worktree. Work that is not saved is kept", .delete, off: deleteAgeOffReason(draft), age: $draft.delete, fallback: defaultDeleteAfterDays)
            }
            if let failure { Label(failure, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange) }
        }
        .onAppear(perform: load)
        .onChange(of: draft) { save() }
    }

    private func row(_ title: String, _ detail: String, _ field: SessionAgeField, off: String?, first: Bool = false, age: Binding<SessionAge>, fallback: Int) -> some View {
        let key = field == .archive ? "archive" : "delete"
        let days = Binding(get: { if case .days(let days) = age.wrappedValue { days } else { fallback } }, set: { age.wrappedValue = .days($0) })
        return SettingsTabRow(title: title, detail: off ?? detail, first: first, problem: off == nil ? problems[field] : nil) {
            HStack(spacing: 10) {
                if age.wrappedValue != .never {
                    NumberField(key: key, value: days, unparsable: $unparsable, parse: { Int($0) }, format: { String($0) }, step: { $0 + $1 >= 1 ? $0 + $1 : nil })
                    Text("days").font(.caption).foregroundStyle(.secondary)
                }
                ChoicePopUp(
                    label: title, options: [(value: false, title: "Days"), (value: true, title: "Never")],
                    selection: Binding(get: { age.wrappedValue == .never }, set: { never in
                        unparsable.remove(key)
                        age.wrappedValue = never ? .never : .days(fallback)
                    }),
                    width: 110
                )
            }
            .disabled(off != nil)
        }
        .foregroundStyle(off == nil && problems[field] == nil ? Color.primary : off == nil ? Color.orange : Color.secondary)
    }

    private func load() {
        do {
            saved = sessionAges(chatJSON: try currentChatConfig())
            draft = saved
            failure = nil
        } catch {
            failure = "chat.json could not be read: \(error.localizedDescription)"
        }
    }

    /// Writes the file, read again just now; nothing while a field is refused (its line says why).
    private func save() {
        guard draft != saved, problems.isEmpty else { return }
        do {
            guard let updated = applyingSessionAges(draft, to: try currentChatConfig()) else {
                failure = "chat.json is not a JSON object, so it was not changed."
                return
            }
            try writeCurrentChatConfig(updated)
            saved = draft
            failure = nil
        } catch {
            FileHandle.standardError.write(Data("carrier: saving chat.json failed: \(error)\n".utf8))
            failure = "Could not save chat.json: \(error.localizedDescription)"
        }
    }
}
