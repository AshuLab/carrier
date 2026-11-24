import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Errors returned when saving a chosen image into the app's `project-icons` folder.
public enum ProjectIconStoreError: Error, LocalizedError, Equatable, Sendable {
    case unreadableImage
    case encodingFailed

    public var errorDescription: String? {
        switch self {
        case .unreadableImage: "The chosen file could not be read as an image."
        case .encodingFailed: "The image could not be saved as a PNG."
        }
    }
}

/// Manages the copied, reduced PNGs for project icons inside `<carrierFolder>/app/project-icons/` (docs/specs/projects.md, ADR 0041).
public struct ProjectIconStore: Sendable, Equatable {
    public static let maxPixelSize: Int = 256

    public let folder: String
    public let directory: URL

    public init(folder: String) {
        self.folder = folder
        self.directory = URL(fileURLWithPath: CarrierPlaces(folder: folder).projectIcons, isDirectory: true)
    }

    public static func current() -> ProjectIconStore {
        ProjectIconStore(folder: currentCarrierFolder())
    }

    /// URL inside `project-icons` for `fileName`, or nil when `fileName` is empty or tries to leave the folder.
    public func fileURL(for fileName: String?) -> URL? {
        guard let fileName, fileName.isEmpty == false else { return nil }
        guard fileName != ".", fileName != "..", fileName.contains("/") == false, fileName.contains("\\") == false else { return nil }
        guard (fileName as NSString).lastPathComponent == fileName else { return nil }
        let candidate = directory.appendingPathComponent(fileName, isDirectory: false)
        guard candidate.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL else { return nil }
        return candidate
    }

    /// URL for `fileName` only when that regular file exists on disk; nil when missing or invalid.
    public func existingURL(for fileName: String?, fileManager: FileManager = .default) -> URL? {
        guard let url = fileURL(for: fileName) else { return nil }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue == false else { return nil }
        return url
    }

    /// Reads `sourceURL`, scales it down to at most `maxPixelSize` on its longest side, writes a PNG with a random name into `project-icons`,
    /// deletes `previous` if given, and returns the new file name.
    @discardableResult
    public func save(from sourceURL: URL, replacing previous: String? = nil, fileManager: FileManager = .default) throws -> String {
        let data = try Self.pngData(from: sourceURL)
        return try writePNG(data, replacing: previous, fileManager: fileManager)
    }

    /// Scales `image` down to at most `maxPixelSize` on its longest side, writes a PNG with a random name into `project-icons`, deletes
    /// `previous` if given, and returns the new file name.
    @discardableResult
    public func save(cgImage image: CGImage, replacing previous: String? = nil, fileManager: FileManager = .default) throws -> String {
        let data = try Self.pngData(from: image)
        return try writePNG(data, replacing: previous, fileManager: fileManager)
    }

    /// Removes the copied image named `fileName` if it is inside `project-icons`; a missing file is ignored.
    public func delete(_ fileName: String?, fileManager: FileManager = .default) {
        guard let url = fileURL(for: fileName) else { return }
        try? fileManager.removeItem(at: url)
    }

    /// Returns whether ImageIO recognizes `sourceURL` as a readable image.
    public static func canRead(_ sourceURL: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else { return false }
        return CGImageSourceGetCount(source) > 0
    }

    /// Encodes the image at `sourceURL` as PNG bytes with its longest side at most `maxPixelSize` pixels.
    public static func pngData(from sourceURL: URL, maxPixelSize: Int = maxPixelSize) throws -> Data {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil), CGImageSourceGetCount(source) > 0 else {
            throw ProjectIconStoreError.unreadableImage
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ProjectIconStoreError.unreadableImage
        }
        return try pngData(from: image, maxPixelSize: maxPixelSize)
    }

    /// Encodes `image` as PNG bytes with its longest side at most `maxPixelSize` pixels.
    public static func pngData(from image: CGImage, maxPixelSize: Int = maxPixelSize) throws -> Data {
        let scaled = try downscaled(image, maxPixelSize: maxPixelSize)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw ProjectIconStoreError.encodingFailed
        }
        CGImageDestinationAddImage(destination, scaled, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ProjectIconStoreError.encodingFailed
        }
        return data as Data
    }

    private func writePNG(_ data: Data, replacing previous: String?, fileManager: FileManager) throws -> String {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileName = "\(UUID().uuidString.lowercased()).png"
        guard let destination = fileURL(for: fileName) else { throw ProjectIconStoreError.encodingFailed }
        try data.write(to: destination, options: .atomic)
        if let previous, previous != fileName { delete(previous, fileManager: fileManager) }
        return fileName
    }

    private static func downscaled(_ image: CGImage, maxPixelSize: Int) throws -> CGImage {
        let width = image.width, height = image.height
        guard maxPixelSize > 0, width > maxPixelSize || height > maxPixelSize else { return image }
        let scale = Double(maxPixelSize) / Double(max(width, height))
        let targetWidth = max(1, Int((Double(width) * scale).rounded()))
        let targetHeight = max(1, Int((Double(height) * scale).rounded()))
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ProjectIconStoreError.encodingFailed
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        guard let result = context.makeImage() else { throw ProjectIconStoreError.encodingFailed }
        return result
    }
}
