import Foundation

// The About window's links (docs/specs/macos-app-redesign.md, story 31). The icon, name, version and copyright come
// from the app bundle: the system's About panel shows them.

public struct AboutLink: Equatable {
    public var title: String
    public var url: URL
}

/// The repository, where the links and the star lead.
public let repositoryURL = "https://github.com/AshuLab/carrier"

public func aboutLinks(bundle: Bundle? = nil, locale: Locale = .current) -> [AboutLink] {
    [
        (Copy.aboutLinkReleaseNotes(bundle: bundle, locale: locale), "https://github.com/AshuLab/carrier/releases"),
        (Copy.aboutLinkDocumentation(bundle: bundle, locale: locale), "https://github.com/AshuLab/carrier/tree/main/docs"),
        (Copy.aboutLinkGitHub(bundle: bundle, locale: locale), repositoryURL),
    ].compactMap { title, url in browserURL(url).map { AboutLink(title: title, url: $0) } }
}
