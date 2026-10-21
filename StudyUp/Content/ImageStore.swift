import Foundation
import UIKit

/// Image files referenced from card text as `![](image:<id>)` — the same syntax the Mac web app uses.
/// An image never changes once saved, so syncing images is only "send the ones the other side lacks".
nonisolated struct ImageStore: Sendable {
    static let shared = ImageStore(
        directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Images", directoryHint: .isDirectory)
    )

    let directory: URL

    /// Longest side kept for images added on the phone, matching the web app.
    static let maxDimension: CGFloat = 2000

    private static let types: [(ext: String, mime: String, matches: (Data) -> Bool)] = [
        ("png", "image/png", { $0.starts(with: [0x89, 0x50, 0x4E, 0x47]) }),
        ("jpg", "image/jpeg", { $0.starts(with: [0xFF, 0xD8, 0xFF]) }),
        ("gif", "image/gif", { $0.starts(with: [0x47, 0x49, 0x46, 0x38]) }),
        ("webp", "image/webp", { $0.starts(with: [0x52, 0x49, 0x46, 0x46]) && $0.count > 12 && $0[8..<12].elementsEqual("WEBP".utf8) }),
    ]

    enum ImageError: LocalizedError {
        case unreadable
        case unsupported

        var errorDescription: String? {
            switch self {
            case .unreadable: "That image couldn’t be read."
            case .unsupported: "Only PNG, JPEG, GIF and WebP images are supported."
            }
        }
    }

    // MARK: - Files

    func url(for id: UUID) -> URL? {
        Self.types.lazy
            .map { directory.appending(path: "\(id.uuidString.lowercased()).\($0.ext)") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    func contains(_ id: UUID) -> Bool {
        url(for: id) != nil
    }

    func data(for id: UUID) -> (data: Data, mime: String)? {
        guard let url = url(for: id), let data = try? Data(contentsOf: url) else { return nil }
        let mime = Self.types.first { url.pathExtension == $0.ext }?.mime ?? "application/octet-stream"
        return (data, mime)
    }

    /// Stores image bytes as they are, e.g. downloaded from the Mac. Existing ids are left alone.
    func save(_ data: Data, id: UUID) throws {
        guard let type = Self.types.first(where: { $0.matches(data) }) else { throw ImageError.unsupported }
        guard !contains(id) else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appending(path: "\(id.uuidString.lowercased()).\(type.ext)"), options: .atomic)
    }

    /// Adds an image picked on the phone: scaled down if large and stored as JPEG. Returns its id.
    func add(_ data: Data) throws -> UUID {
        guard let image = UIImage(data: data) else { throw ImageError.unreadable }
        let scale = min(1, Self.maxDimension / max(image.size.width, image.size.height))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let jpeg = resized.jpegData(compressionQuality: 0.85) else { throw ImageError.unreadable }
        let id = UUID()
        try save(jpeg, id: id)
        return id
    }

    /// Every image id stored on this device.
    func storedIDs() -> [UUID] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return files.compactMap { UUID(uuidString: ($0 as NSString).deletingPathExtension) }
    }

    /// Deletes images no card refers to. Recent ones are kept, since an image is added as soon as
    /// it's picked, before its card is saved. Returns how many were removed.
    @discardableResult
    func removeUnused(referenced: Set<UUID>, now: Date = .now, keepNewerThan: TimeInterval = 7 * 86_400) -> Int {
        var removed = 0
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files {
            guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent), !referenced.contains(id) else { continue }
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? now
            guard now.timeIntervalSince(modified) >= keepNewerThan else { continue }
            if (try? FileManager.default.removeItem(at: file)) != nil { removed += 1 }
        }
        return removed
    }

    // MARK: - References in card text

    private static let reference = /!\[[^\]]*\]\(image:([0-9a-fA-F-]{36})\)/

    static func snippet(for id: UUID) -> String {
        "![](image:\(id.uuidString.lowercased()))"
    }

    /// The images a card's text refers to, in order.
    static func references(in text: String) -> [UUID] {
        text.matches(of: reference).compactMap { UUID(uuidString: String($0.output.1)) }
    }

    /// Every image the given cards use.
    @MainActor
    static func references(in cards: [Card]) -> Set<UUID> {
        Set(cards.flatMap { references(in: $0.front) + references(in: $0.back) })
    }

    /// Text with image references swapped for a marker, for places that only show plain text.
    static func replacingReferences(in text: String, with marker: String = "📷") -> String {
        text.replacing(reference) { _ in marker }
    }

    /// Text with one image's reference removed, along with the line break it sat on.
    static func removingReference(to id: UUID, from text: String) -> String {
        let snippet = snippet(for: id)
        let lines = text.components(separatedBy: "\n").filter { $0.trimmingCharacters(in: .whitespaces).lowercased() != snippet }
        return lines.joined(separator: "\n").replacingOccurrences(of: snippet, with: "", options: .caseInsensitive)
    }

    /// Text with an image reference added on its own line at the end.
    static func appendingReference(to id: UUID, to text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? snippet(for: id) : "\(trimmed)\n\(snippet(for: id))"
    }
}
