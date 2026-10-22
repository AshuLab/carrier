import CarrierCore
import SwiftUI

/// The Files changed tab: the total as pills, then one card per agent session. Working sessions open, merged ones folded.
struct FilesChangedView: View {
    let files: FilesReply?
    /// Sections the person flipped from their default.
    @State private var flipped: Set<String> = []

    var body: some View {
        let model = filesChangedModel(files)
        if model.isEmpty {
            EmptyStateView(state: .noFilesChanged).frame(minHeight: 260)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                FilesSummary(model: model)
                ForEach(model.sections, id: \.id) { section in
                    let open = section.openByDefault != flipped.contains(section.id)
                    FileSectionView(section: section, open: open && section.files.isEmpty == false) {
                        if flipped.insert(section.id).inserted == false { flipped.remove(section.id) }
                    }
                }
            }
        }
    }
}

/// The epic's total, labelled as such: `7 files`, `+166`, `−12` and the five squares of the two, for every session together.
private struct FilesSummary: View {
    let model: FilesChangedModel

    var body: some View {
        HStack(spacing: 6) {
            Text("Epic total").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.trailing, 2)
            Pill { Text("\(model.fileCount)").fontWeight(.semibold).foregroundStyle(.primary); Text(model.fileCount == 1 ? "file" : "files") }
            Pill { Text("+\(model.added)").fontWeight(.semibold).foregroundStyle(.green) }
            Pill { Text("−\(model.removed)").fontWeight(.semibold).foregroundStyle(.red) }
            DiffSquares(added: model.added, removed: model.removed).padding(.leading, 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Epic total: \(model.fileCount) \(model.fileCount == 1 ? "file" : "files"), \(model.added) lines added, \(model.removed) removed")
        .help("Every session together: each file counted once, the lines of every session added up")
    }
}

/// A small capsule of the grey the session headers' count pills use.
private struct Pill<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 4) { content }
            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(Capsule().fill(Color.secondary.opacity(0.16)))
    }
}

private struct FileSectionView: View {
    let section: FileSection
    let open: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 11) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(section.title).fontWeight(.semibold).lineLimit(1)
                        HStack(spacing: 5) {
                            Pill {
                                Image(systemName: "doc.text").font(.system(size: 10, weight: .semibold))
                                Text("\(section.files.count)").fontWeight(.semibold).foregroundStyle(.primary)
                                Text(section.files.count == 1 ? "file" : "files")
                            }
                            Pill { Text("+\(section.added)").fontWeight(.semibold).foregroundStyle(.green) }
                            Pill { Text("−\(section.removed)").fontWeight(.semibold).foregroundStyle(.red) }
                        }
                    }
                    Spacer(minLength: 8)
                    HStack(spacing: 4) {
                        if section.working == false { Image(systemName: "arrow.triangle.merge").font(.system(size: 9, weight: .bold)) }
                        Text(section.working ? "not merged yet" : "merged")
                    }
                    .font(.caption.weight(.medium)).foregroundStyle(section.working ? Color.blue : .purple)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill((section.working ? Color.blue : .purple).opacity(0.18)))
                    // a round button, as in the session headers: it says the whole header folds
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(open ? 90 : 0))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.secondary.opacity(0.16)))
                        .opacity(section.files.isEmpty ? 0 : 1)
                }
                .padding(.horizontal, 12).padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(section.files.isEmpty)
            if open {
                ForEach(section.files, id: \.path) { row in
                    Divider()
                    FileRowView(row: row)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.secondary.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.secondary.opacity(0.12), lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// The file's icon: a bundled SVG, or the category's symbol. The images are read once.
struct FileIconView: View {
    let icon: FileIcon
    @MainActor private static var images: [URL: NSImage] = [:]

    var body: some View {
        switch icon {
        case .bundled(_, let url):
            if let image = Self.image(url) {
                Image(nsImage: image).resizable().scaledToFit().frame(width: 18, height: 18)
            }
        case .symbol(let name):
            Image(systemName: name).font(.system(size: 15)).foregroundStyle(.secondary)
        }
    }

    @MainActor private static func image(_ url: URL) -> NSImage? {
        if let known = images[url] { return known }
        guard let image = NSImage(contentsOf: url) else { return nil }
        images[url] = image
        return image
    }
}

/// A file: its icon, the name with the directory under it, and how big the change is, as the two numbers and five squares.
struct FileRowView: View {
    let row: FileRow

    var body: some View {
        HStack(spacing: 9) {
            FileIconView(icon: row.icon).frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.name).fontWeight(.medium).lineLimit(1)
                if row.directory.isEmpty == false || row.alsoIn.isEmpty == false { subtitle }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(row.directory + row.name)
            HStack(spacing: 4) {
                Text("+\(row.added)").foregroundStyle(.green)
                Text("−\(row.removed)").foregroundStyle(.red)
            }
            .monospacedDigit().font(.callout)
            DiffSquares(added: row.added, removed: row.removed)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    /// The directory, cut in the middle when it does not fit; the warning keeps its room.
    private var subtitle: some View {
        HStack(spacing: 6) {
            Text(row.directory).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            if row.alsoIn.isEmpty == false {
                Text("⚠ also in \(row.alsoIn.joined(separator: ", "))").foregroundStyle(.orange).lineLimit(1).fixedSize()
            }
        }
        .font(.caption)
    }
}

/// Five small squares, green for added and red for removed in proportion, grey for the rest.
private struct DiffSquares: View {
    let added: Int
    let removed: Int

    var body: some View {
        let squares = diffSquares(added: added, removed: removed)
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index < squares.green ? Color.green : index < squares.green + squares.red ? Color.red : Color.secondary.opacity(0.2))
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityHidden(true)
    }
}
