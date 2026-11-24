import Foundation

/// The folders the tests read from disk, found from the path of the file that asks, whatever folder of the tests it sits in.
/// The package is the nearest folder above the file that holds `Package.swift`; the repository is the folder above the package.
struct TestPaths: Equatable {
    let fixtures: URL
    let sources: URL
    let root: URL
}

func testPaths(from file: String = #filePath) -> TestPaths {
    var folder = URL(fileURLWithPath: file).deletingLastPathComponent()
    while FileManager.default.fileExists(atPath: folder.appendingPathComponent("Package.swift").path) == false {
        let parent = folder.deletingLastPathComponent()
        guard parent != folder else { fatalError("no Package.swift above \(file)") }
        folder = parent
    }
    return TestPaths(
        fixtures: folder.appendingPathComponent("Tests/Fixtures"),
        sources: folder.appendingPathComponent("Sources"),
        root: folder.deletingLastPathComponent()
    )
}
