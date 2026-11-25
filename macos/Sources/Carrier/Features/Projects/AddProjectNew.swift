import AppKit
import CarrierCore
import SwiftUI

// The New project… form of the shared sheet: a name and where the folder is made.

extension AddProjectSheet {
    /// The form of New project…: a name (a plain folder name) and where it is made, `<projects folder>/local/<name>` with Choose… for this one only. Create asks the
    /// host to make the folder and register it, then closes the sheet and opens the project's page; a name whose folder is there is refused with the reason and nothing is written.
    var newProjectForm: some View {
        let reason = form.problem(taken: model.isTaken)
        return VStack(spacing: Tokens.Space.none) {
            VStack(alignment: .leading, spacing: Tokens.Space.s14) {
                HStack(spacing: Tokens.Space.s12) {
                    Glyph(.folderPlus, size: 16).foregroundStyle(.tint)
                        .frame(width: 36, height: 36)
                        .background(RoundedRectangle(cornerRadius: Tokens.Radius.control).fill(.tint.opacity(0.16)))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                        Text("New project").scaledFont(16, weight: .semibold)
                        Text(mode.actsAtOnce ? "An empty git folder, added as a project." : "An empty git folder, made when you send the first message.").scaledFont(12).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: Tokens.Space.s6) {
                    Text("Name").sectionLabel()
                    TextField("", text: $form.name, prompt: Text("my-project"))
                        .settingsField(icon: .folder, focused: $nameFocused)
                        .autocorrectionDisabled()
                        .writingToolsBehavior(.disabled)
                        .accessibilityLabel("Name of the new project")
                        .onSubmit(createProject)
                        .onChange(of: form.name) { problem = nil }
                    Text("Letters, numbers, dots and dashes").scaledFont(11).foregroundStyle(.tertiary)
                }
                VStack(alignment: .leading, spacing: Tokens.Space.s6) {
                    Text(mode.actsAtOnce ? "Create in" : "Will be created in").sectionLabel()
                    HStack(spacing: Tokens.Space.s8) {
                        Text(form.destinationLine().dropFirst("Creates ".count))
                            .scaledFont(11, design: .monospaced)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(form.folder)
                        if mode.actsAtOnce {
                            Button("Choose…", action: chooseNewProjectParent)
                                .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
                                .accessibilityLabel("Choose where the new project is made")
                        }
                        Spacer(minLength: 0)
                    }
                }
                if let line = problem ?? reason { ProblemLine(text: line) }
            }
            .padding(.horizontal, Tokens.Space.s24)
            .padding(.top, Tokens.Space.s22)
            .padding(.bottom, Tokens.Space.s16)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
            SettingsDivider()
            HStack(spacing: Tokens.Space.s12) {
                Button("Back") {
                    problem = nil
                    creating = false
                }
                .buttonStyle(SecondaryCapsuleButtonStyle())
                Spacer(minLength: 8)
                Button("Cancel") { dismiss() }
                    .buttonStyle(SecondaryCapsuleButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(mode.actsAtOnce ? "Create" : "Use this project", action: createProject)
                    .buttonStyle(PrimaryCapsuleButtonStyle())
                    .disabled(form.canCreate(taken: model.isTaken) == false || making)
            }
            .padding(.horizontal, Tokens.Space.s20)
            .padding(.vertical, Tokens.Space.s12)
        }
        .frame(width: 580, height: 460)
        .onAppear { nameFocused = true }
    }

    private func createProject() {
        guard form.canCreate(taken: model.isTaken), making == false else { return }
        if let newSession {
            newSession.choose(newProject: form.name)
            dismiss()
            return
        }
        making = true
        problem = nil
        let name = form.name
        let parent = form.chosenParent
        Task {
            defer { making = false }
            do {
                let folder = try await model.createProject(name, into: parent)
                dismiss()
                openProject(folder)
            } catch ControlError.remote(let refusal) {
                problem = refusal.shown()
            } catch {
                problem = hostNotRunning
            }
        }
    }

    /// The folder panel for the folder this one project is made in (the default is left as it is); refused for a folder inside Carrier's own.
    private func chooseNewProjectParent() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: form.parent)
        panel.prompt = "Choose"
        panel.message = "Choose the folder the new project is made in"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let refusal = projectsFolderRefusal(url.path, carrierFolder: currentCarrierFolder()) {
            problem = refusal.shown()
            return
        }
        problem = nil
        form.chosenParent = url.path
    }
}
