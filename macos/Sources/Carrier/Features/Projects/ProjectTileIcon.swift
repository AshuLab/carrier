import AppKit
import CarrierCore
import SwiftUI

extension ProjectColor {
    /// Muted hues chosen to match `ProjectIcon.palette` so white initials and marks keep readable contrast in both light and dark appearances.
    var color: Color {
        switch self {
        case .red: Color(hue: 0.98, saturation: 0.56, brightness: 0.64)
        case .orange: Color(hue: 0.06, saturation: 0.60, brightness: 0.62)
        case .yellow: Color(hue: 0.125, saturation: 0.56, brightness: 0.52)
        case .green: Color(hue: 0.375, saturation: 0.54, brightness: 0.51)
        case .teal: Color(hue: 0.47, saturation: 0.54, brightness: 0.52)
        case .blue: Color(hue: 0.61, saturation: 0.56, brightness: 0.64)
        case .purple: Color(hue: 0.76, saturation: 0.52, brightness: 0.64)
        case .pink: Color(hue: 0.90, saturation: 0.52, brightness: 0.64)
        }
    }
}

/// Loads and caches copied project icon PNGs from `project-icons`, returning nil when the file is missing or unreadable so the tile falls back to color and mark.
@MainActor enum ProjectIconImageCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(named fileName: String?, in store: ProjectIconStore = .current()) -> NSImage? {
        guard let url = store.existingURL(for: fileName) else {
            if let stale = store.fileURL(for: fileName) { cache.removeObject(forKey: stale.path as NSString) }
            return nil
        }
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let loaded = NSImage(contentsOf: url), loaded.isValid, loaded.size.width > 0, loaded.size.height > 0 else { return nil }
        cache.setObject(loaded, forKey: key)
        return loaded
    }
}

extension ProjectIcon {
    /// The icon of a project's tile: its color (a chosen one, else the palette's at the tile's index), its mark or initials, and its copied image from
    /// `imageFolder` (the Carrier folder's own when not given).
    @MainActor init(tile: ProjectTile, imageFolder: String? = nil, working: Bool = false, background: Bool = false, finished: Bool = false) {
        let color: Color
        switch tile.color {
        case .named(let named): color = named.color
        case .hashed(let index): color = Self.palette[index % Self.palette.count]
        }
        let store = imageFolder.map(ProjectIconStore.init(folder:)) ?? .current()
        let content: (initials: String, mark: AppIcon?) =
            switch tile.content {
            case .initials(let letters): (letters, nil)
            case .mark(let icon): ("", icon)
            }
        self.init(
            initials: content.initials, color: color, mark: content.mark, image: tile.image.flatMap { ProjectIconImageCache.image(named: $0, in: store) },
            working: working, background: background, finished: finished
        )
    }

    /// The icon of the project whose folder is `base`: what the person set on it, else made from `name` and `colorKey` as it was before projects.
    @MainActor init(base: String, name: String, colorKey: String, working: Bool = false, background: Bool = false, finished: Bool = false) {
        let tile = projectTile(path: base, in: ProjectsModel.shared.rows, fallback: projectTile(name: name, colorKey: colorKey))
        self.init(tile: tile, working: working, background: background, finished: finished)
    }

    /// The icon of an epic's repository `owner/name`: its project's when one has it as its `origin`, else made from `name` and `colorKey` as it was before projects.
    @MainActor init(repo: String, name: String, colorKey: String, working: Bool = false) {
        self.init(tile: projectTile(repo: repo, in: ProjectsModel.shared.rows, fallback: projectTile(name: name, colorKey: colorKey)), working: working)
    }
}
