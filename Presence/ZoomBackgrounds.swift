import AppKit
import AVFoundation
import Foundation
import ImageIO

/// A background file from this Mac’s Zoom library, or a file the person chose.
struct ZoomBackground: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case image
        case video
    }

    enum Origin: String, Sendable {
        case yours
        case library
        case chosen
    }

    var id: String
    var url: URL
    var kind: Kind
    var origin: Origin
    var modified: Date
    var title: String
}

/// Reads whatever Zoom saved for the person using this Mac. No background is bundled.
enum ZoomBackgroundLibrary {
    static func load() -> [ZoomBackground] {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/zoom.us/data", isDirectory: true)
        let folders: [(String, ZoomBackground.Origin)] = [
            ("VirtualBkgnd_Custom", .yours),
            ("VirtualBkgnd_Video", .yours),
            ("VirtualBkgnd_Default", .library)
        ]
        var items: [ZoomBackground] = []
        for (name, origin) in folders {
            items.append(contentsOf: contents(of: root.appendingPathComponent(name, isDirectory: true), origin: origin))
        }
        let yours = items
            .filter { $0.origin != .library }
            .sorted { $0.modified > $1.modified }
        let library = items
            .filter { $0.origin == .library }
            .sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
        return uniqueTitles(yours + library)
    }

    static func item(forChosenFile url: URL) -> ZoomBackground? {
        guard let kind = kind(of: url) else { return nil }
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        let name = url.deletingPathExtension().lastPathComponent
        return ZoomBackground(
            id: url.path,
            url: url,
            kind: kind,
            origin: .chosen,
            modified: values?.contentModificationDate ?? Date(),
            title: name.isEmpty ? "Chosen file" : name
        )
    }

    static func thumbnails(for items: [ZoomBackground]) -> [String: NSImage] {
        var made: [String: NSImage] = [:]
        for item in items {
            if let image = thumbnail(for: item) {
                made[item.id] = image
            }
        }
        return made
    }

    private static func contents(of directory: URL, origin: ZoomBackground.Origin) -> [ZoomBackground] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard values?.isRegularFile == true, let kind = kind(of: url) else { return nil }
            let modified = values?.contentModificationDate ?? Date()
            let day = modified.formatted(.dateTime.month(.abbreviated).day())
            let title: String
            switch (origin, kind) {
            case (.yours, .video): title = "Video · \(day)"
            case (.yours, .image): title = "Yours · \(day)"
            case (.library, .video): title = "Video"
            case (.library, .image): title = "Included"
            case (.chosen, _): title = url.deletingPathExtension().lastPathComponent
            }
            return ZoomBackground(
                id: url.path,
                url: url,
                kind: kind,
                origin: origin,
                modified: modified,
                title: title
            )
        }
    }

    private static func uniqueTitles(_ items: [ZoomBackground]) -> [ZoomBackground] {
        var seen: [String: Int] = [:]
        return items.map { item in
            guard item.origin != .library else { return item }
            let count = seen[item.title, default: 0] + 1
            seen[item.title] = count
            guard count > 1 else { return item }
            var copy = item
            let clock = item.modified.formatted(date: .omitted, time: .shortened)
            copy.title = "\(item.title) · \(clock)"
            return copy
        }
    }

    private static func kind(of url: URL) -> ZoomBackground.Kind? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 16)) ?? Data()
        if data.starts(with: [0xFF, 0xD8, 0xFF]) || data.starts(with: [0x89, 0x50, 0x4E, 0x47]) || data.starts(with: [0x42, 0x4D]) {
            return .image
        }
        if data.count >= 12, String(data: data[4..<8], encoding: .ascii) == "ftyp" {
            return .video
        }
        return nil
    }

    private static func thumbnail(for item: ZoomBackground) -> NSImage? {
        switch item.kind {
        case .image:
            guard let source = CGImageSourceCreateWithURL(item.url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 160,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return menuImage(image)
        case .video:
            let asset = AVURLAsset(url: item.url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 160, height: 90)
            let time = CMTime(seconds: 0.4, preferredTimescale: 600)
            guard let image = try? generator.copyCGImage(at: time, actualTime: nil) else { return nil }
            return menuImage(image)
        }
    }

    private static func menuImage(_ image: CGImage) -> NSImage {
        let aspect = CGFloat(image.width) / CGFloat(max(image.height, 1))
        let height: CGFloat = 36
        let width = min(72, (height * aspect).rounded())
        return NSImage(cgImage: image, size: NSSize(width: width, height: height))
    }
}
