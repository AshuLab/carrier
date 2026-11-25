import AppKit
import CarrierCore
import QuickLookUI
import SwiftUI

/// The files of a message (or of the box) looked at in the app, one at a time with Quick Look (images, PDFs, text), the arrows going to the
/// previous and the next one. Esc closes it.
struct AttachmentPreview: View {
    let files: [AttachedFile]
    @State var index: Int
    @Environment(\.dismiss) private var dismiss

    init(files: [AttachedFile], start: AttachedFile) {
        self.files = files
        _index = State(initialValue: files.firstIndex { $0.id == start.id } ?? 0)
    }

    private var file: AttachedFile { files[index] }

    var body: some View {
        VStack(spacing: Tokens.Space.none) {
            HStack(spacing: Tokens.Space.s10) {
                Text(file.name).font(.headline).lineLimit(1).truncationMode(.middle)
                if files.count > 1 { Text(Copy.chatAttachmentPosition(index: index + 1, count: files.count)).font(.callout).foregroundStyle(.secondary).monospacedDigit() }
                Spacer(minLength: 0)
                Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.path)]) } label: { Label(Copy.chatShowInFinder(), icon: .folder) }
                    .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
                IconButton(icon: .close, name: Copy.chatClose()) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, Tokens.Space.s16).padding(.vertical, Tokens.Space.s10)
            Divider()
            QuickLook(path: file.path)
                .overlay(alignment: .leading) { step(.chevronLeft, Copy.chatPrevious(), -1) }
                .overlay(alignment: .trailing) { step(.chevronRight, Copy.chatNext(), 1) }
        }
        .windowSheetSize(maxWidth: 900)
    }

    /// The arrow at one side; it is not drawn where there is nothing further, and the arrow keys do the same.
    @ViewBuilder private func step(_ symbol: AppIcon, _ name: String, _ by: Int) -> some View {
        if files.indices.contains(index + by) {
            Button { index += by } label: {
                Glyph(symbol, size: 14).frame(width: 36, height: 36).contentShape(Circle())
            }
            .buttonStyle(.plain).glassEffect(.regular.interactive(), in: .circle)
            .keyboardShortcut(by < 0 ? .leftArrow : .rightArrow, modifiers: [])
            .help(name).accessibilityLabel(name).padding(Tokens.Space.s12)
        }
    }
}

/// Quick Look's own view of one file.
private struct QuickLook: NSViewRepresentable {
    let path: String

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.previewItem = URL(fileURLWithPath: path) as NSURL
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? URL)?.path != path { view.previewItem = URL(fileURLWithPath: path) as NSURL }
    }
}
