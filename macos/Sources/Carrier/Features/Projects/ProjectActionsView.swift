import AppKit
import CarrierCore
import SwiftUI

/// A project's Actions screen (docs/specs/projects.md, Scope 16; docs/adr/0039): two groups (`New worktree` and `After clone`), each listing
/// its actions and ending in Add action. Valid edits write at once to `projects.json`; a blank name or command is not written and shows as a problem.
struct ProjectActionsView: View {
    let savedActions: [ProjectAction]
    let save: ([ProjectAction]) async -> Bool

    @State private var drafts: [ProjectActionDraft]
    @State private var savedById: [UUID: ProjectAction]
    @State private var lastWritten: [ProjectAction]

    init(savedActions: [ProjectAction], save: @escaping ([ProjectAction]) async -> Bool) {
        self.savedActions = savedActions
        self.save = save
        let initial = savedActions.map { ProjectActionDraft(action: $0) }
        _drafts = State(initialValue: initial)
        _savedById = State(initialValue: Dictionary(uniqueKeysWithValues: initial.map { ($0.id, $0.action) }))
        _lastWritten = State(initialValue: savedActions)
    }

    var body: some View {
        Group {
            group(
                when: .newWorktree,
                footer: Copy.projectsActionsFooterNewWorktree()
            )
            group(
                when: .afterClone,
                footer: Copy.projectsActionsFooterAfterClone()
            )
        }
        .writingToolsBehavior(.disabled)
        .onChange(of: drafts) { commit() }
        .onChange(of: savedActions) { syncExternal($1) }
    }

    private func group(when: ProjectActionWhen, footer: String) -> some View {
        let items = drafts.filter { $0.action.when == when }
        return SettingsGroup(title: when.title(), footer: footer) {
            ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                actionRows(item, first: offset == 0)
            }
            Button { add(when) } label: { Label(Copy.projectsAddAction(), icon: .plus).labelStyle(.titleAndIcon) }
                .buttonStyle(HoverTextButtonStyle(tint: nil))
                .padding(.vertical, Tokens.Space.s10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) { if items.isEmpty == false { SettingsDivider() } }
        }
    }

    @ViewBuilder private func actionRows(_ item: ProjectActionDraft, first: Bool) -> some View {
        let problems = projectActionProblems(item.action)
        let label = item.action.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let named = label.isEmpty ? Copy.projectsActionFallbackName() : label
        SettingsTabRow(title: Copy.projectsName(), detail: "", first: first, problem: problems[.name]) {
            HStack(spacing: Tokens.Space.s10) {
                TextField("", text: binding(item.id, \.name), prompt: Text(Copy.projectsActionNamePrompt()))
                    .accessibilityLabel(Copy.projectsName()).settingsField(width: 200)
                Toggle(Copy.projectsActionOn(), isOn: binding(item.id, \.on))
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                    .accessibilityLabel(Copy.projectsActionEnable(name: named))
                    .help(item.action.on ? Copy.projectsActionTurnOff() : Copy.projectsActionTurnOn())
                IconButton(icon: .trash, name: Copy.projectsActionDelete(name: named)) { delete(item.id) }
            }
        }
        .accessibilityElement(children: .contain)
        SettingsTabRow(title: Copy.projectsActionCommand(), detail: Copy.projectsActionCommandDetail(), problem: problems[.command]) {
            TextField("", text: binding(item.id, \.command), prompt: Text(Copy.projectsActionCommandPrompt()))
                .scaledFont(11.5, design: .monospaced)
                .accessibilityLabel(Copy.projectsActionCommand())
                .settingsField(width: 282)
                .writingToolsBehavior(.disabled)
        }
        .accessibilityElement(children: .contain)
        SettingsTabRow(title: Copy.projectsActionIfFails(), detail: "") {
            ChoicePopUp(
                label: Copy.projectsActionIfFails(),
                options: ProjectActionOnFail.allCases.map { (value: $0, title: $0.title()) },
                selection: binding(item.id, \.onFail)
            )
        }
    }

    private func binding<Value>(_ id: UUID, _ keyPath: WritableKeyPath<ProjectAction, Value>) -> Binding<Value> {
        Binding(
            get: { drafts.first { $0.id == id }?.action[keyPath: keyPath] ?? ProjectAction(when: .newWorktree)[keyPath: keyPath] },
            set: { value in
                guard let index = drafts.firstIndex(where: { $0.id == id }) else { return }
                drafts[index].action[keyPath: keyPath] = value
            }
        )
    }

    private func add(_ when: ProjectActionWhen) {
        drafts.append(ProjectActionDraft(action: ProjectAction(when: when)))
    }

    private func delete(_ id: UUID) {
        drafts.removeAll { $0.id == id }
        savedById.removeValue(forKey: id)
    }

    private func commit() {
        let toWrite = mergedProjectActions(drafts: drafts, saved: savedById)
        guard toWrite != lastWritten else { return }
        Task {
            if await save(toWrite) {
                lastWritten = toWrite
                let liveIds = Set(drafts.map(\.id))
                savedById = savedById.filter { liveIds.contains($0.key) }
                for draft in drafts where projectActionProblems(draft.action).isEmpty {
                    savedById[draft.id] = draft.action
                }
            }
        }
    }

    private func syncExternal(_ latest: [ProjectAction]) {
        guard latest != lastWritten else { return }
        let refreshed = latest.map { ProjectActionDraft(action: $0) }
        drafts = refreshed
        savedById = Dictionary(uniqueKeysWithValues: refreshed.map { ($0.id, $0.action) })
        lastWritten = latest
    }
}
