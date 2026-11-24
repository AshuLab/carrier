import Foundation
import Testing
@testable import CarrierCore

@Test(arguments: [
    ("src/app.ts", "typescript"), ("src/View.tsx", "react_ts"), ("a.js", "javascript"), ("a.mjs", "javascript"),
    ("package.json", "json"), ("README.md", "markdown"), ("ci/build.yml", "yaml"), ("ci/build.yaml", "yaml"),
    ("app.css", "css"), ("index.html", "html"), ("a/b/View.swift", "swift"), ("tool.py", "python"), ("main.go", "go"),
    ("lib.rs", "rust"), ("scripts/run.sh", "console"), ("schema.sql", "database"), ("schema.prisma", "prisma"),
    ("Cargo.lock", "lock"), ("pnpm-lock.yaml", "lock"), ("package-lock.json", "lock"),
    ("Dockerfile", "docker"), ("logo.png", "image"), ("photo.JPG", "image"), ("icon.svg", "image"),
    ("src/token.test.ts", "typescript"),
])
func eachCoveredNameAndExtensionGetsItsBundledIcon(path: String, name: String) throws {
    guard case .bundled(let bundledName, let url) = fileIcon(path) else {
        Issue.record("\(path) got no bundled icon")
        return
    }
    #expect(bundledName == name)
    #expect(FileManager.default.fileExists(atPath: url.path), "\(path): \(url.path)")
}

@Test(arguments: [
    ("archive.xyz", AppIcon.file), ("LICENSE", .file), (".gitignore", .file), ("", .file),
    ("notes.txt", .fileText), ("Makefile", .terminal), ("data.toml", .braces), ("theme.scss", .brush),
])
func anythingElseGetsTheSymbolOfItsCategory(path: String, symbol: AppIcon) {
    #expect(fileIcon(path) == .symbol(symbol))
}

@Test func everyBundledIconNameHasItsFileAndTheLicenceTextIsTheUpstreamOne() throws {
    let names = Set(["ts", "tsx", "js", "jsx", "json", "md", "yml", "css", "html", "swift", "py", "go", "rs", "sh", "sql", "prisma", "lock", "png"].compactMap { bundledIconName("a.\($0)") })
    for name in names {
        #expect(Bundle.module.url(forResource: name, withExtension: "svg", subdirectory: "FileIcons") != nil, Comment(rawValue: name))
    }
    let licence = try String(contentsOf: #require(fileIconsLicenceURL), encoding: .utf8)
    #expect(licence.hasPrefix("The MIT License (MIT)\nCopyright (c) 2025 Material Extensions"))
}
