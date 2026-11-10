import Foundation

// The About window's links (docs/specs/macos-app-redesign.md, story 31). The icon, name, version and copyright come
// from the app bundle: the system's About panel shows them.

public struct AboutLink: Equatable {
    public var title: String
    public var url: URL
}

public let aboutLinks: [AboutLink] = [
    ("Release notes", "https://github.com/AshuLab/carrier/releases"),
    ("Documentation", "https://github.com/AshuLab/carrier/tree/main/docs"),
    ("GitHub", "https://github.com/AshuLab/carrier"),
].compactMap { title, url in browserURL(url).map { AboutLink(title: title, url: $0) } }
