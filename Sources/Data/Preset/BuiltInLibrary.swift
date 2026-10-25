import Foundation
import CryptoKit
import GRDB

/// Offline artwork becomes ordinary owned images; the local marker is deliberately not backed up.
enum BuiltInLibrary {
    static let initializedKey = "builtinLibrary.initialized.v1"
    struct Room: Decodable, Sendable { let name: String; let description: String; let assetPath: String }
    struct BrandAsset: Decodable, Sendable { let key: String; let names: [String]; let assetPath: String }
    struct Catalog: Decodable, Sendable { let formatVersion: Int; let rooms: [Room]; let brands: [BrandAsset] }
    struct StorageTemplate: Decodable, Identifiable, Sendable {
        let id: String; let name: String; let assetPath: String; let sha256: String; let description: String; let version: Int
    }
    private struct StorageCatalog: Decodable { let formatVersion: Int; let templates: [StorageTemplate] }

    static func assetURL(_ path: String) throws -> URL {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.first == "builtin", parts.count >= 2,
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              let root = SkinResources.bundle.resourceURL else { throw ValidationError.invalid("内置图片路径无效") }
        let url = root.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: url.path) else { throw ValidationError.invalid("内置资料缺失，请更新应用") }
        return url
    }
    static func catalog() throws -> Catalog {
        let value = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: assetURL("builtin/catalog.json")))
        guard value.formatVersion == 1, value.rooms.count == 6, Set(value.rooms.map(\.name)).count == 6,
              value.brands.count == 14, Set(value.brands.map(\.key)).count == 14,
              value.rooms.allSatisfy({ !$0.name.isEmpty }) else { throw ValidationError.invalid("内置资料清单无效") }
        _ = try brandAssets(value)
        return value
    }
    static func templates() throws -> [StorageTemplate] {
        let value = try JSONDecoder().decode(StorageCatalog.self, from: Data(contentsOf: assetURL("builtin/storage/catalog.json")))
        guard value.formatVersion == 1, value.templates.count == 4, Set(value.templates.map(\.id)).count == 4,
              value.templates.allSatisfy({ !$0.id.isEmpty && !$0.name.isEmpty && $0.version > 0 && $0.assetPath.hasPrefix("builtin/storage/") && $0.sha256.count == 64 }) else { throw ValidationError.invalid("内置收纳素材清单无效") }
        return value.templates
    }
    private static func normalize(_ name: String) -> String { name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    private static func brandAssets(_ catalog: Catalog) throws -> [String: String] {
        var result: [String: String] = [:]
        for brand in catalog.brands {
            guard !brand.key.isEmpty, !brand.names.isEmpty else { throw ValidationError.invalid("内置品牌清单无效") }
            for name in brand.names {
                let key = normalize(name)
                guard !key.isEmpty, result[key] == nil || result[key] == brand.assetPath else { throw ValidationError.invalid("内置品牌别名冲突") }
                result[key] = brand.assetPath
            }
        }
        return result
    }

    static func copyImage(_ asset: String, sha256: String? = nil, imagesDirectory: URL? = nil) throws -> String {
        let data = try Data(contentsOf: assetURL(asset))
        if let sha256 {
            guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == sha256 else { throw ValidationError.invalid("内置收纳图片校验失败，请更新应用") }
        }
        guard let path = ImageFileHelper.save(imageData: data, imagesDirectory: imagesDirectory) else { throw ValidationError.invalid("无法保存内置图片，请检查存储空间") }
        return path
    }

    static func initialize(db queue: DatabaseQueue, defaults: UserDefaults = .standard, imagesDirectory: URL? = nil) throws {
        guard !defaults.bool(forKey: initializedKey) else { return }
        let catalog = try catalog(), assets = try brandAssets(catalog)
        var staged = [String]()
        do {
            try queue.write { db in
                try PresetData.seed(db)
                var sort = (try Location.fetchAll(db).map(\.sortOrder).max() ?? -1) + 1
                for room in catalog.rooms {
                    if var existing = try Location.filter(Column("name") == room.name).fetchOne(db) {
                        if existing.imageUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                            let image = try copyImage(room.assetPath, imagesDirectory: imagesDirectory); staged.append(image)
                            // Preserve IDs, custom descriptions, ordering and timestamps.
                            existing.imageUrl = image; try existing.update(db)
                        }
                    } else {
                        let image = try copyImage(room.assetPath, imagesDirectory: imagesDirectory); staged.append(image)
                        var value = Location(name: room.name, description: room.description, imageUrl: image, sortOrder: sort)
                        try value.insert(db); sort += 1
                    }
                }
                for var brand in try Brand.fetchAll(db) {
                    if (brand.logoUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true), let asset = assets[normalize(brand.name)] {
                        let image = try copyImage(asset, imagesDirectory: imagesDirectory); staged.append(image)
                        brand.logoUrl = image; try brand.update(db)
                    }
                }
            }
            // Set only after commit. Later deletions, renames and removed images stay removed.
            defaults.set(true, forKey: initializedKey)
        } catch {
            try? ImageFileHelper.deleteUnreferenced(paths: staged, db: queue, imagesDirectory: imagesDirectory)
            throw error
        }
    }

    static func prepareNewBrand(_ brand: Brand, imagesDirectory: URL? = nil) throws -> Brand {
        guard brand.logoUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true,
              let asset = try brandAssets(catalog())[normalize(brand.name)] else { return brand }
        var result = brand; result.logoUrl = try copyImage(asset, imagesDirectory: imagesDirectory); return result
    }

    static func adoptTemplates(_ ids: Set<String>, roomId: Int64, db queue: DatabaseQueue, imagesDirectory: URL? = nil) throws {
        let selected = try templates().filter { ids.contains($0.id) }
        guard !ids.isEmpty, selected.count == ids.count else { throw ValidationError.invalid("请选择有效的收纳示意图") }
        var staged = [String]()
        do {
            try queue.write { db in
                guard try Location.fetchOne(db, key: roomId) != nil else { throw ValidationError.invalid("房间已删除，请重新选择") }
                var nodes = try StorageNode.fetchAll(db)
                let rooms = Set(try Location.fetchAll(db).map(\.id))
                var sort = (nodes.filter { $0.locationId == roomId && $0.parentNodeId == nil }.map(\.sortOrder).max() ?? -1) + 1
                for template in selected {
                    var node = StorageNode(locationId: roomId, name: template.name)
                    node.description = template.description; node.sortOrder = sort
                    var candidate = node; candidate.id = Int64.max
                    try StorageTree.validate(nodes + [candidate], rooms: rooms)
                    let image = try copyImage(template.assetPath, sha256: template.sha256, imagesDirectory: imagesDirectory); staged.append(image)
                    node.imageUrl = image; try node.insert(db); nodes.append(node); sort += 1
                }
            }
        } catch {
            try? ImageFileHelper.deleteUnreferenced(paths: staged, db: queue, imagesDirectory: imagesDirectory)
            throw error
        }
    }
}
