import AppKit
import CarrierCore
import SwiftUI

/// Settings as a screen of the main window: the readiness banner, four tabs, and the Engine tab. The other three tabs wait
/// for their slices.
struct SettingsScreen: View {
    @ObservedObject var setup: SetupController = .shared
    @State private var tab = Tab.engine

    enum Tab: String, CaseIterable { case engine = "Engine", notifications = "Notifications", menuBar = "Menu bar", general = "General" }

    var body: some View {
        let model = engineTab(setup.settings, detecting: setup.detecting)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ReadinessBannerView(banner: model.banner, detecting: setup.detecting) { setup.detect() }
                if let message = setup.message {
                    Label(message, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange)
                }
                Picker("Tab", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                if tab == .engine {
                    VStack(spacing: 0) {
                        ForEach(model.rows, id: \.field) { EngineRowView(row: $0, setup: setup) }
                    }
                    .padding(.horizontal, 14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.07)))
                } else {
                    Text("Coming soon").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 120)
                }
            }
            .padding(18)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .navigationTitle("Settings")
    }
}

struct ReadinessBannerView: View {
    let banner: ReadinessBanner
    let detecting: Bool
    let detectAgain: () -> Void

    var body: some View {
        let tint: Color = banner.state == .ready ? .green : .orange
        HStack(spacing: 12) {
            if banner.state == .detecting {
                ProgressView().controlSize(.small)
            } else {
                StatusDot(found: banner.state == .ready)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(banner.title).fontWeight(.semibold)
                Text(banner.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Detect again", action: detectAgain).disabled(detecting)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16).fill(tint.opacity(0.13)))
        .accessibilityElement(children: .combine)
    }
}

/// The round check or exclamation mark in front of a banner or a row.
struct StatusDot: View {
    let found: Bool

    var body: some View {
        Image(systemName: found ? "checkmark" : "exclamationmark")
            .font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(Circle().fill(found ? Color.green : Color.orange))
            .accessibilityLabel(found ? "Found" : "Not found")
    }
}

struct EngineRowView: View {
    let row: EngineRow
    @ObservedObject var setup: SetupController
    @State private var editing = false

    var body: some View {
        HStack(spacing: 12) {
            StatusDot(found: row.found)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title).fontWeight(.medium)
                if editing {
                    TextField("PATH", text: $setup.settings.path).textFieldStyle(.roundedBorder).font(.system(.caption, design: .monospaced))
                        .onSubmit { editing = false }
                } else if let value = row.value {
                    Text(value).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle).help(value)
                    Text(row.hint).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Not found · choose where it is").font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 8)
            if let path = row.revealPath {
                Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
            }
            Button(row.choice == .edit ? (editing ? "Done" : "Edit…") : "Choose…") {
                switch row.choice {
                case .edit: editing.toggle()
                case .file, .folder: choose()
                }
            }
        }
        .padding(.vertical, 10).frame(minHeight: 46)
        .overlay(alignment: .top) { Divider().opacity(row.field == .carrier ? 0 : 1) }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = row.choice == .file
        panel.canChooseDirectories = row.choice == .folder
        panel.canCreateDirectories = row.choice == .folder
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.prompt = "Choose"
        if let current = row.revealPath {
            panel.directoryURL = URL(fileURLWithPath: current).deletingLastPathComponent()
        }
        if panel.runModal() == .OK, let url = panel.url { setup.settings[row.field] = url.path }
    }
}
