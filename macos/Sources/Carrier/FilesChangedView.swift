import CarrierCore
import SwiftUI

/// The Files changed tab: the total, then one block per agent session. Working sessions open, merged ones folded.
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
                Text(model.summary).font(.callout).foregroundStyle(.secondary)
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

private struct FileSectionView: View {
    let section: FileSection
    let open: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(open ? 90 : 0)).opacity(section.files.isEmpty ? 0 : 1)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(section.title).font(.body.weight(.semibold))
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(section.files.isEmpty)
            if open {
                VStack(spacing: 0) {
                    ForEach(section.files, id: \.path) { FileRowView(row: $0) }
                }
                .padding(.top, 6)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.07)))
    }

    private var subtitle: String {
        let count = section.files.count
        return "\(count) \(count == 1 ? "file" : "files") · +\(section.added) −\(section.removed) · "
            + (section.working ? "not merged yet" : "merged into the epic")
    }
}

struct FileRowView: View {
    let row: FileRow

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: row.category.symbol).foregroundStyle(.secondary).frame(width: 18)
            PathText(directory: row.directory, name: row.name)
            if row.alsoIn.isEmpty == false {
                Text("⚠ also in \(row.alsoIn.joined(separator: ", "))").font(.caption).foregroundStyle(.orange)
                    .lineLimit(1).fixedSize()
            }
            Text("+\(row.added)").foregroundStyle(.green)
            Text("−\(row.removed)").foregroundStyle(.red)
        }
        .font(.callout.monospacedDigit()).padding(.vertical, 3)
    }
}

/// A path on one line: when it does not fit the directory gives way, cut in the middle, and the file name stays whole.
struct PathText: View {
    let directory: String
    let name: String

    var body: some View {
        HStack(spacing: 0) {
            Text(directory).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            Text(name).lineLimit(1).layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(directory + name)
    }
}
