import AppKit
import CarrierCore
import ImageIO
import SwiftUI

/// A file handed to the chat, as a chip of glass: a badge by kind (the thumbnail itself for an image), the name over its size or what holds it
/// back, and a × while the pointer is over it when it can be taken out. A click shows the file in Finder.
struct AttachmentChip: View {
    let file: AttachedFile
    var remove: (() -> Void)?
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
        HStack(spacing: 9) {
            badge
            VStack(alignment: .leading, spacing: 0) {
                Text(Self.shortened(file.name)).font(.scaled(12.5, weight: .semibold)).lineLimit(1)
                Text(file.problemText ?? file.detail).font(.scaled(11)).foregroundStyle(tint ?? .secondary).lineLimit(1)
            }
            if let remove {
                Button(action: remove) {
                    Image(systemName: "xmark").font(.scaled(9, weight: .bold)).foregroundStyle(.secondary)
                        .frame(width: 18, height: 18).background(Circle().fill(Color.primary.opacity(0.14))).contentShape(Circle())
                }
                .buttonStyle(.plain).help("Take it out").accessibilityLabel("Remove \(file.name)")
                .opacity(hovering || tint != nil ? 1 : 0)
                .animation(.easeOut(duration: 0.12), value: hovering)
            }
        }
        .padding(.leading, 5).padding(.trailing, remove == nil ? 12 : 7).padding(.vertical, 5)
        // as wide as its words and no wider (the name is cut by `shortened`): a flexible frame would stretch the glass and leave the × in its middle
        .fixedSize(horizontal: true, vertical: false)
        .glassEffect(.regular.tint(tint?.opacity(0.3)), in: .rect(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onHover { hovering = $0 }
        .onTapGesture { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.path)]) }
        .help(file.path)
        .task(id: file.path) { thumbnail = await Self.thumbnail(of: file) }
        .accessibilityElement(children: .combine)
    }

    private var badge: some View {
        ZStack {
            if let thumbnail {
                Image(nsImage: thumbnail).resizable().scaledToFill()
            } else {
                Image(systemName: symbol).font(.scaled(15, weight: .medium)).foregroundStyle(.white)
            }
        }
        .frame(width: 32, height: 32)
        // the badge of the session notices: the colour itself, vivid, with the symbol in white
        .background(color)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.16), lineWidth: 0.5))
        .accessibilityHidden(true)
    }

    private var symbol: String {
        if file.problem != nil { return "exclamationmark" }
        return switch file.kind {
        case .image: "photo"
        case .pdf: "doc.richtext"
        case .folder: "folder.fill"
        case .log: "text.alignleft"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .data: "tablecells"
        case .archive: "archivebox"
        case .other: "doc"
        }
    }

    private var color: Color {
        if file.problem != nil { return tint ?? .red }
        return switch file.kind {
        case .image: Color(red: 0.43, green: 0.36, blue: 0.91)
        case .pdf: Color(red: 0.88, green: 0.27, blue: 0.35)
        case .folder: Color(red: 0.89, green: 0.63, blue: 0.19)
        case .log: Color(red: 0.42, green: 0.47, blue: 0.58)
        case .code: Color.themeAccent
        case .data: Color(red: 0.12, green: 0.64, blue: 0.58)
        case .archive: Color(red: 0.62, green: 0.43, blue: 0.28)
        case .other: Color(red: 0.48, green: 0.50, blue: 0.56)
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

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(files) { AttachmentChip(file: $0) }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .task(id: paths) {
            let folder = carrierFolder(environment: ProcessInfo.processInfo.environment, home: NSHomeDirectory())
            files = paths.map { attachedFile(at: URL(fileURLWithPath: $0), carrierFolder: folder) }
        }
    }
}
