import Foundation
@preconcurrency import GRDB
#if canImport(UIKit)
import UIKit
#endif

enum ImageFileHelper {
    private static var imagesDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("images")
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Copy image data to images directory with UUID filename. Returns the stored path.
    static func save(imageData: Data) -> String? {
        let uuid = UUID().uuidString
        guard let directory = safeDirectory(imagesDir) else { return nil }
        let url = directory.appendingPathComponent("\(uuid).jpg")
        do {
            try imageData.write(to: url)
            return url.path
        } catch {
            print("ImageFileHelper: failed to save image: \(error)")
            return nil
        }
    }

    #if canImport(UIKit)
    /// Copy picked UIImage to images directory. Returns stored path.
    static func save(image: UIImage) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.9) else { return nil }
        return save(imageData: data)
    }
    #endif

    static func isOwnedFile(_ path: String) -> Bool {
        isOwnedFile(path, imagesDirectory: imagesDir)
    }

    static func isOwnedFile(_ path: String, imagesDirectory: URL) -> Bool {
        ownedFileURL(for: path, imagesDirectory: imagesDirectory) != nil
    }

    /// Delete image at stored path.
    static func delete(path: String) {
        delete(path: path, imagesDirectory: imagesDir)
    }

    static func delete(path: String, imagesDirectory: URL) {
        guard let url = ownedFileURL(for: path, imagesDirectory: imagesDirectory) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Delete multiple images at paths.
    static func delete(paths: [String]) {
        for path in paths { delete(path: path) }
    }

    static func deleteUnreferenced(paths: [String], db: DatabaseQueue, imagesDirectory: URL? = nil) throws {
        let directory = imagesDirectory ?? imagesDir
        let referenced = try db.read { db -> Set<String> in
            var paths = Set<String>()
            for item in try Item.fetchAll(db) {
                paths.formUnion(item.allImagePaths)
                if let chart = item.sizeChartImageUrl { paths.insert(chart) }
            }
            for node in try StorageNode.fetchAll(db) { if let image = node.imageUrl { paths.insert(image) } }
            for draft in try ItemDraft.fetchAll(db) { paths.formUnion(draft.allImagePaths) }
            for coordinate in try Coordinate.fetchAll(db) { paths.formUnion(coordinate.imageUrls.values) }
            for log in try OutfitLog.fetchAll(db) { paths.formUnion(log.imageUrls.values) }
            for location in try Location.fetchAll(db) { if let image = location.imageUrl { paths.insert(image) } }
            for brand in try Brand.fetchAll(db) { if let logo = brand.logoUrl { paths.insert(logo) } }
            for key in ["profileAvatarPath", "paymentCalendarBackgroundPath"] {
                if let path = UserDefaults.standard.string(forKey: key), !path.isEmpty { paths.insert(path) }
            }
            return Set(paths.compactMap { ownedFileURL(for: $0, imagesDirectory: directory)?.path })
        }
        let candidates = Set(paths.compactMap { ownedFileURL(for: $0, imagesDirectory: directory)?.path })
        for path in candidates.subtracting(referenced) {
            delete(path: path, imagesDirectory: directory)
        }
    }

    /// Resolve stored path to URL for display.
    static func fileURL(for path: String) -> URL {
        fileURL(for: path, imagesDirectory: imagesDir)
    }

    static func fileURL(for path: String, imagesDirectory: URL) -> URL {
        if let url = URL(string: path), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil {
            return url
        }
        if let url = ownedFileURL(for: path, imagesDirectory: imagesDirectory) { return url }
        // Callers expect a URL. An unresolved local image must not become a
        // request to read another sandbox, a temporary file, or a directory.
        let placeholderDirectory = safeDirectory(imagesDirectory)
            ?? imagesDirectory.deletingLastPathComponent().resolvingSymlinksInPath()
        return placeholderDirectory.appendingPathComponent(".missing-image-\(UUID().uuidString)")
    }

    /// Container UUIDs may change after an app update. Rewrite all existing
    /// image references together before repositories or editors load them.
    @discardableResult
    static func migrateStoredPaths(db queue: DatabaseQueue, imagesDirectory: URL? = nil) throws -> Int {
        let directory = imagesDirectory ?? imagesDir
        let updated = try queue.write { db in
            func image(_ path: String?) -> String? {
                guard let path else { return nil }
                return ownedFileURL(for: path, imagesDirectory: directory)?.path ?? path
            }
            func images(_ list: StringList) -> StringList {
                StringList(list.values.map { image($0) ?? $0 })
            }
            var updated = 0
            for var item in try Item.fetchAll(db) {
                let urls = images(item.imageUrls)
                let chart = image(item.sizeChartImageUrl)
                let charts = images(item.sizeChartImageUrls)
                if urls.values != item.imageUrls.values || chart != item.sizeChartImageUrl || charts.values != item.sizeChartImageUrls.values {
                    item.imageUrls = urls
                    item.sizeChartImageUrl = chart
                    item.sizeChartImageUrls = charts
                    try item.update(db)
                    updated += 1
                }
            }
            for var node in try StorageNode.fetchAll(db) {
                let url = image(node.imageUrl)
                if url != node.imageUrl { node.imageUrl = url; try node.update(db); updated += 1 }
            }
            for var draft in try ItemDraft.fetchAll(db) {
                let photos = images(draft.imagePaths), charts = images(draft.detailImagePaths)
                if photos.values != draft.imagePaths.values || charts.values != draft.detailImagePaths.values {
                    draft.imagePaths = photos; draft.detailImagePaths = charts; try draft.update(db); updated += 1
                }
            }
            for var coordinate in try Coordinate.fetchAll(db) {
                let urls = images(coordinate.imageUrls)
                if urls.values != coordinate.imageUrls.values {
                    coordinate.imageUrls = urls
                    try coordinate.update(db)
                    updated += 1
                }
            }
            for var log in try OutfitLog.fetchAll(db) {
                let urls = images(log.imageUrls)
                if urls.values != log.imageUrls.values {
                    log.imageUrls = urls
                    try log.update(db)
                    updated += 1
                }
            }
            for var location in try Location.fetchAll(db) {
                let url = image(location.imageUrl)
                if url != location.imageUrl {
                    location.imageUrl = url
                    try location.update(db)
                    updated += 1
                }
            }
            for var brand in try Brand.fetchAll(db) {
                let url = image(brand.logoUrl)
                if url != brand.logoUrl {
                    brand.logoUrl = url
                    try brand.update(db)
                    updated += 1
                }
            }
            return updated
        }
        for key in ["profileAvatarPath", "paymentCalendarBackgroundPath"] {
            if let old = UserDefaults.standard.string(forKey: key),
               let path = ownedFileURL(for: old, imagesDirectory: directory)?.path, old != path {
                UserDefaults.standard.set(path, forKey: key)
            }
        }
        return updated
    }

    private static func safeDirectory(_ directory: URL) -> URL? {
        guard directory.isFileURL else { return nil }
        let canonical = directory.deletingLastPathComponent().resolvingSymlinksInPath()
            .appendingPathComponent(directory.lastPathComponent, isDirectory: true).standardizedFileURL
        // Follow system aliases in the parent (e.g. /var -> /private/var),
        // but never an images directory redirected outside that parent.
        guard canonical.resolvingSymlinksInPath().path == canonical.path else { return nil }
        return canonical
    }

    private static func ownedFileURL(for path: String, imagesDirectory: URL) -> URL? {
        guard let directory = safeDirectory(imagesDirectory), !path.isEmpty else { return nil }
        let decodedComponents = (path.removingPercentEncoding ?? path).split(separator: "/")
        guard !decodedComponents.contains(".."), !decodedComponents.contains("."), !path.contains("\0") else { return nil }
        let source: URL
        if let url = URL(string: path), let scheme = url.scheme {
            guard scheme.lowercased() == "file", url.host == nil || url.host == "" || url.host == "localhost" else { return nil }
            source = url
        } else {
            guard path.hasPrefix("/") else { return nil }
            source = URL(fileURLWithPath: path)
        }
        let components = source.pathComponents
        guard !components.contains(".."), !components.contains("."), !source.lastPathComponent.isEmpty else { return nil }
        let isCurrent = source.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path == directory.path
        let suffix = Array(components.suffix(7))
        let isOldSandbox = suffix.count == 7
            && suffix[0] == "Containers" && suffix[1] == "Data" && suffix[2] == "Application"
            && UUID(uuidString: suffix[3]) != nil && suffix[4] == "Documents" && suffix[5] == "images"
        guard isCurrent || isOldSandbox else { return nil }
        let candidate = directory.appendingPathComponent(source.lastPathComponent).standardizedFileURL
        guard candidate.deletingLastPathComponent().path == directory.path else { return nil }
        if let attributes = try? FileManager.default.attributesOfItem(atPath: candidate.path) {
            // Reject directories and symbolic links, including links to a
            // different app or a file outside the owned images directory.
            guard attributes[.type] as? FileAttributeType == .typeRegular else { return nil }
        } else if !isCurrent {
            // A matching filename is useful only if it survived the move.
            return nil
        }
        guard candidate.resolvingSymlinksInPath().path == candidate.path else { return nil }
        return candidate
    }
}
