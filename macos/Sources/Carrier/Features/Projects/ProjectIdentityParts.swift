import AppKit
import CarrierCore
import SwiftUI

/// The project's Name field: writes on Return or focus loss, reverts on failure, updates when another process changes `projects.json`, and
/// clears `name` (falling back to the folder's name) when emptied.
struct ProjectNameField: View {
    let stored: String
    let prompt: String
    let commit: (String) async -> Bool
    @State private var draft: String
    @FocusState private var focused: Bool

    init(stored: String, prompt: String, commit: @escaping (String) async -> Bool) {
        self.stored = stored
        self.prompt = prompt
        self.commit = commit
        _draft = State(initialValue: stored)
    }

    var body: some View {
        TextField("", text: $draft, prompt: Text(prompt))
            .settingsField(width: settingsSelectWidth, focused: $focused)
            .onSubmit(save)
            .onChange(of: focused) { _, now in if now == false { save() } }
            .onChange(of: stored) { _, now in if focused == false { draft = now } }
            .onDisappear(perform: save)
            .accessibilityLabel("Name")
    }

    private func save() {
        let next = normalizedProjectName(draft) ?? ""
        let current = normalizedProjectName(stored) ?? ""
        if next == current {
            draft = current
            return
        }
        let written = draft
        Task {
            if await commit(written) {
                draft = next
            } else {
                draft = stored
            }
        }
    }
}

/// A tag capsule with a cross button to remove it.
struct ProjectTagChip: View {
    let tag: String
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Text(tag).font(.scaled(12, weight: .medium)).lineLimit(1).truncationMode(.tail)
            Button(action: remove) {
                Glyph(.close, size: 9, bold: true).foregroundStyle(.secondary)
                    .frame(width: 16, height: 16).background(Circle().fill(Color.primary.opacity(0.12))).contentShape(Circle())
            }
            .buttonStyle(.plain).help("Remove \(tag)").accessibilityLabel("Remove tag \(tag)")
        }
        .padding(.leading, 10).padding(.trailing, 5).padding(.vertical, 3)
        .background(Capsule().fill(Color.primary.opacity(0.07)))
    }
}

/// The Change… popover for a project's icon: eight colours, eight marks and Choose image…, matching `AccountEditor`'s 30 pt grid.
struct ProjectIconPopover: View {
    let selectedColor: ProjectColor?
    let selectedMark: AppIcon?
    let hasImage: Bool
    let setColor: (ProjectColor?) -> Void
    let setMark: (AppIcon?) -> Void
    let chooseImage: () -> Void
    let reset: () -> Void

    private static let tile: CGFloat = 30, gap: CGFloat = 8, columns = 8
    private static let gridWidth = CGFloat(columns) * tile + CGFloat(columns - 1) * gap
    private var grid: [GridItem] { Array(repeating: GridItem(.fixed(Self.tile), spacing: Self.gap), count: Self.columns) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Color").sectionLabel()
                    Spacer(minLength: 8)
                    if selectedColor != nil || selectedMark != nil || hasImage {
                        Button("Reset", action: reset).buttonStyle(HoverTextButtonStyle(tint: nil)).font(.scaled(11))
                    }
                }
                LazyVGrid(columns: grid, alignment: .leading, spacing: Self.gap) {
                    ForEach(ProjectColor.allCases, id: \.self) { choice in
                        let on = hasImage == false && selectedColor == choice
                        let name = choice.rawValue.capitalized
                        Button { setColor(on ? nil : choice) } label: {
                            Circle().fill(choice.color)
                                .frame(width: 20, height: 20).padding(5)
                                .overlay(Circle().strokeBorder(Color.primary, lineWidth: 2).opacity(on ? 1 : 0))
                                .frame(width: Self.tile, height: Self.tile)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).help(name).accessibilityLabel(name).accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Mark").sectionLabel()
                let tint = (hasImage ? nil : selectedColor)?.color ?? Color.primary
                LazyVGrid(columns: grid, alignment: .leading, spacing: Self.gap) {
                    ForEach(projectIconMarks, id: \.self) { choice in
                        let on = hasImage == false && selectedMark == choice
                        let name = choice.rawValue.capitalized
                        Button { setMark(on ? nil : choice) } label: {
                            Glyph(choice, size: 15).foregroundStyle(tint)
                                .frame(width: Self.tile, height: Self.tile)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12)))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: on ? 2 : 0))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).help(name).accessibilityLabel(name).accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            SettingsDivider()
            Button(action: chooseImage) {
                Label("Choose image…", icon: .photo).labelStyle(.titleAndIcon)
            }
            .buttonStyle(SecondaryCapsuleButtonStyle())
            .controlSize(.small)
        }
        .frame(width: Self.gridWidth, alignment: .leading)
    }
}
