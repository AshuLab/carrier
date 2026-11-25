import AppKit
import CarrierCore
import ImageIO
import SwiftUI

/// A file handed to the chat, as a chip of glass: a badge by kind (the thumbnail itself for an image), the name over its size or what holds it
/// back, and a × while the pointer is over it when it can be taken out. A click opens `open` (the preview, for a file that can be looked at);
/// without one it shows the file in Finder.
struct AttachmentChip: View {
    let file: AttachedFile
    var remove: (() -> Void)?
    var open: (() -> Void)?
    @State private var hovering = false
    @State private var thumbnail: NSImage?

    private var tint: Color? {
        switch file.problem {
        case .carrierOwn?: .orange
        case nil: nil
        default: .red
        }
    }

    var body: some View {
        HStack(spacing: Tokens.Space.s10) {
            badge
            VStack(alignment: .leading, spacing: Tokens.Space.none) {
                Text(Self.shortened(file.name)).font(.scaled(12.5, weight: .semibold)).lineLimit(1)
                Text(file.problemText ?? file.detail).font(.scaled(11)).foregroundStyle(tint ?? .secondary).lineLimit(1)
            }
            if let remove {
                Button(action: remove) {
                    Glyph(.close, size: 9).foregroundStyle(.secondary)
                        .frame(width: 18, height: 18).background(Circle().fill(Color.primary.opacity(0.14))).contentShape(Circle())
                }
                .buttonStyle(.plain).help("Take it out").accessibilityLabel("Remove \(file.name)")
                .opacity(hovering || tint != nil ? 1 : 0)
                .animation(.easeOut(duration: 0.12), value: hovering)
            }
        }
        .padding(.leading, Tokens.Space.s5).padding(.trailing, remove == nil ? Tokens.Space.s12 : Tokens.Space.s8).padding(.vertical, Tokens.Space.s5)
        // as wide as its words and no wider (the name is cut by `shortened`): a flexible frame would stretch the glass and leave the × in its middle
        .fixedSize(horizontal: true, vertical: false)
        .chatSurface(.regular.tint(tint?.opacity(0.3)), flat: tint.map { $0.opacity(0.16) } ?? Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
        .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
        .onHover { hovering = $0 }
        .onTapGesture { if let open { open() } else { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.path)]) } }
        .help(file.path)
        .task(id: file.path) { thumbnail = await Self.thumbnail(of: file) }
        .accessibilityElement(children: .combine)
    }

    private var badge: some View {
        ZStack {
            if let thumbnail {
                Image(nsImage: thumbnail).resizable().scaledToFill()
            } else {
                Glyph(symbol, size: 15, bold: true).foregroundStyle(.white)
            }
        }
        .frame(width: 32, height: 32)
        // the badge of the session notices: the colour itself, vivid, with the symbol in white
        .background(color)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.tile))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.tile).strokeBorder(.white.opacity(0.16), lineWidth: 0.5))
        .accessibilityHidden(true)
    }

    private var symbol: AppIcon {
        if file.problem != nil { return .exclamation }
        return switch file.kind {
        case .image: .photo
        case .pdf: .fileDescription
        case .folder: .folder
        case .log: .alignLeft
        case .code: .code
        case .data: .table
        case .archive: .archive
        case .other: .file
        }
    }

    private var color: Color {
        if file.problem != nil { return tint ?? .red }
        return switch file.kind {
        case .image: Color(Tokens.Attachment.image)
        case .pdf: Color(Tokens.Attachment.pdf)
        case .folder: Color(Tokens.Attachment.folder)
        case .log: Color(Tokens.Attachment.log)
        case .code: Color.themeAccent
        case .data: Color(Tokens.Attachment.data)
        case .archive: Color(Tokens.Attachment.archive)
        case .other: Color(Tokens.Attachment.other)
        }
    }

    /// A name longer than 28 characters is cut in its middle, which keeps the extension.
    private static func shortened(_ name: String, limit: Int = 28) -> String {
        guard name.count > limit else { return name }
        let head = (limit - 1) * 2 / 3
        return name.prefix(head) + "…" + name.suffix(limit - 1 - head)
    }

    /// An image as its own badge, cut small by ImageIO, which does not read all of a large picture to do it.
    private static func thumbnail(of file: AttachedFile) async -> NSImage? {
        guard file.kind == .image, file.problem == nil else { return nil }
        return await Task.detached {
            guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: file.path) as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 96]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { NSImage(cgImage: $0, size: .zero) }
        }.value
    }
}

/// The files that came with a message the person sent, as the chips of the box without their ×; what each is is read when they show.
struct SentAttachments: View {
    let paths: [String]
    @State private var files: [AttachedFile] = []
    @State private var previewing: AttachedFile?

    var body: some View {
        FlowLayout(spacing: Tokens.Space.s8) {
            ForEach(files) { file in AttachmentChip(file: file, open: file.canPreview ? { previewing = file } : nil) }
        }
        .attachmentPreview(of: files, showing: $previewing)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .task(id: paths) {
            let folder = carrierFolder(environment: ProcessInfo.processInfo.environment, home: NSHomeDirectory())
            files = paths.map { attachedFile(at: URL(fileURLWithPath: $0), carrierFolder: folder) }
        }
    }
}

extension AttachedFile {
    /// What Quick Look can show: a file that goes, not a folder.
    var canPreview: Bool { problem == nil && kind != .folder }
}

extension View {
    /// The preview of `files` (the ones that can be looked at) over this view, opened on the one in `showing`.
    func attachmentPreview(of files: [AttachedFile], showing: Binding<AttachedFile?>) -> some View {
        sheet(item: showing) { start in AttachmentPreview(files: files.filter(\.canPreview), start: start).themed() }
    }
}
