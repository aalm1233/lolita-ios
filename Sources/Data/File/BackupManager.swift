import Foundation
import CryptoKit
import ZIPFoundation
@preconcurrency import GRDB

struct BackupData: Codable, Sendable {
    var brands: [Brand]
    var categories: [Category]
    var coordinates: [Coordinate]
    var items: [Item]
    var prices: [Price]
    var payments: [Payment]
    var outfitLogs: [OutfitLog]
    var outfitItemCrossRefs: [OutfitItemCrossRef]
    var styles: [Style]
    var seasons: [Season]
    var locations: [Location]
    var sources: [Source]
    var backupDate: Int64
    var appVersion: String
    var imageData: [String: String]

    var imagePaths: Set<String> {
        var paths = Set(items.flatMap { $0.imageUrls.values })
        paths.formUnion(items.compactMap(\.sizeChartImageUrl))
        paths.formUnion(coordinates.flatMap { $0.imageUrls.values })
        paths.formUnion(outfitLogs.flatMap { $0.imageUrls.values })
        paths.formUnion(locations.compactMap(\.imageUrl))
        paths.formUnion(brands.compactMap(\.logoUrl))
        return paths.filter { !$0.isEmpty }
    }

    var missingImageCount: Int {
        imagePaths.filter { path in
            !["http", "https"].contains(URL(string: path)?.scheme ?? "") && imageData[path] == nil
        }.count
    }
}


/// Owns only temporary files. Keeping this object in the confirmation UI makes
/// the accepted preview immutable even if the source document later changes.
final class PreparedBackup: Sendable {
    let backup: BackupData
    let imageFiles: [String: URL]
    let isZIP: Bool
    private let stagingDirectory: URL?

    var imageCount: Int { Set(imageFiles.values).count + backup.imageData.count }
    var missingImageCount: Int {
        backup.imagePaths.filter {
            !BackupManager.isRemoteImage($0) && imageFiles[$0] == nil && backup.imageData[$0] == nil
        }.count
    }

    init(backup: BackupData, imageFiles: [String: URL] = [:], isZIP: Bool = false, stagingDirectory: URL? = nil) {
        self.backup = backup
        self.imageFiles = imageFiles
        self.isZIP = isZIP
        self.stagingDirectory = stagingDirectory
    }

    deinit {
        if let stagingDirectory { try? FileManager.default.removeItem(at: stagingDirectory) }
    }
}

final class BackupManager: Sendable {
    private let queue: DatabaseQueue
    init(db: DatabaseQueue) { queue = db }

    func snapshot() async throws -> BackupData {
        try await queue.read { db in
            BackupData(brands: try Brand.fetchAll(db), categories: try Category.fetchAll(db),
                       coordinates: try Coordinate.fetchAll(db), items: try Item.fetchAll(db),
                       prices: try Price.fetchAll(db), payments: try Payment.fetchAll(db),
                       outfitLogs: try OutfitLog.fetchAll(db), outfitItemCrossRefs: try OutfitItemCrossRef.fetchAll(db),
                       styles: try Style.fetchAll(db), seasons: try Season.fetchAll(db),
                       locations: try Location.fetchAll(db), sources: try Source.fetchAll(db),
                       backupDate: Int64(Date().timeIntervalSince1970 * 1000), appVersion: "ios-1", imageData: [:])
        }
    }

    func exportJSON() async throws -> Data {
        var backup = try await snapshot()
        for path in backup.imagePaths {
            let url = ImageFileHelper.fileURL(for: path)
            if ImageFileHelper.isOwnedFile(path), let data = try? Data(contentsOf: url) { backup.imageData[path] = data.base64EncodedString() }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    static func preview(_ data: Data) throws -> BackupData {
        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["items"] is [[String: Any]], json["brands"] is [[String: Any]], json["categories"] is [[String: Any]] else {
            throw ValidationError.invalid("这不是有效的 Lolita JSON 备份")
        }
        let version: Int
        if let supplied = json["formatVersion"] {
            guard let number = supplied as? NSNumber, String(cString: number.objCType) != "c",
                  let integer = supplied as? Int else { throw ValidationError.invalid("备份格式版本无效") }
            version = integer
        } else { version = 1 }
        guard (1...2).contains(version) else { throw ValidationError.invalid("此备份来自更新的格式版本，请先更新应用") }
        let tables = ["brands", "categories", "coordinates", "items", "prices", "payments", "outfitLogs",
                      "outfitItemCrossRefs", "styles", "seasons", "locations", "sources"]
        let unsupportedTables = ["legacyCatalogArchives", "syncStates", "remoteBrands", "remoteCategories", "remoteStyles", "remoteSeasons",
                                 "remoteSources", "remoteCoordinates", "remoteItems", "remotePricePlans"]
        let allowed = Set(tables + unsupportedTables + ["backupDate", "appVersion", "formatVersion", "schemaVersion", "imageData"])
        guard Set(json.keys).isSubset(of: allowed) else {
            throw ValidationError.invalid("备份包含未支持的数据类型，暂时无法完整恢复")
        }
        if version == 2 {
            guard (tables + unsupportedTables).allSatisfy({ json[$0] is [[String: Any]] }) else {
                throw ValidationError.invalid("完整备份缺少数据表，无法恢复")
            }
        }
        // These Android tables have no iOS model yet. Do not silently discard
        // actual records while presenting the import as a complete restore.
        for table in unsupportedTables {
            guard let value = json[table], !(value is NSNull) else { continue }
            guard let rows = value as? [Any], rows.isEmpty else {
                throw ValidationError.invalid("备份包含 iOS 尚不支持的共享库或历史图鉴数据，暂时无法完整恢复")
            }
        }
        if let schema = json["schemaVersion"] {
            guard let integer = schema as? Int, (0...20).contains(integer) else {
                throw ValidationError.invalid("此备份来自更新的数据库版本，请先更新应用")
            }
        }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let common: [String: Any] = ["isPreset": false, "createdAt": now, "updatedAt": now]
        let defaults: [String: [String: Any]] = [
            "brands": [:], "categories": ["group": "CLOTHING"], "styles": [:], "seasons": [:], "sources": [:],
            "locations": ["description": "", "sortOrder": 0],
            "coordinates": ["description": "", "imageUrls": [String]()],
            "outfitLogs": ["note": "", "imageUrls": [String]()],
            "items": ["description": "", "imageUrls": [String](), "colors": [String](), "status": "OWNED", "priority": "MEDIUM", "coordinateOrder": 0],
            "prices": [:], "payments": ["isPaid": false, "reminderSet": false], "outfitItemCrossRefs": [:]
        ]
        for (table, fields) in defaults {
            if let supplied = json[table], !(supplied is NSNull), !(supplied is [[String: Any]]) {
                throw ValidationError.invalid("备份中的 \(table) 列表格式无效")
            }
            let rows = json[table] as? [[String: Any]] ?? []
            json[table] = rows.map { row -> [String: Any] in
                var result = common.merging(fields) { _, new in new }
                result.merge(row) { _, new in new }
                if ["items", "coordinates", "outfitLogs"].contains(table), row["imageUrls"] == nil,
                   let image = row["imageUrl"] as? String {
                    result["imageUrls"] = image.isEmpty ? [] : [image]
                }
                if table == "items" { result["colors"] = normalizedLegacyColors(row["colors"] ?? row["color"]) }
                if row["updatedAt"] == nil, let createdAt = row["createdAt"] { result["updatedAt"] = createdAt }
                return result
            }
        }
        if version == 1 {
            var payments = json["payments"] as? [[String: Any]] ?? []
            var nextID = payments.compactMap { ($0["id"] as? NSNumber)?.int64Value }.max() ?? 0
            let prices = json["prices"] as? [[String: Any]] ?? []
            for price in prices {
                guard price["purchaseDate"] != nil, let priceID = price["id"] as? Int64,
                      !payments.contains(where: { ($0["priceId"] as? Int64) == priceID }) else { continue }
                guard nextID < Int64.max else { throw ValidationError.invalid("备份付款记录 ID 超出范围") }
                nextID += 1
                let paidAt = (price["purchaseDate"] as? Int64) ?? (price["createdAt"] as? Int64) ?? now
                payments.append(["id": nextID, "priceId": priceID, "amount": price["totalPrice"] ?? 0,
                                 "dueDate": paidAt, "paidDate": paidAt, "createdAt": price["createdAt"] ?? now,
                                 "isPaid": true, "reminderSet": false])
            }
            json["payments"] = payments
        }
        if json["backupDate"] == nil { json["backupDate"] = now }
        if json["appVersion"] == nil { json["appVersion"] = "legacy" }
        if json["imageData"] == nil { json["imageData"] = [String: String]() }
        let backup = try JSONDecoder().decode(BackupData.self, from: JSONSerialization.data(withJSONObject: json))
        try validate(backup)
        return backup
    }

    private static func validate(_ backup: BackupData) throws {
        for table in [backup.brands.map(\.id), backup.categories.map(\.id), backup.items.map(\.id),
                      backup.coordinates.map(\.id), backup.outfitLogs.map(\.id), backup.prices.map(\.id),
                      backup.payments.map(\.id), backup.styles.map(\.id), backup.seasons.map(\.id),
                      backup.locations.map(\.id), backup.sources.map(\.id)] {
            guard table.allSatisfy({ $0 > 0 }), Set(table).count == table.count else {
                throw ValidationError.invalid("备份包含无效或重复的记录 ID")
            }
        }
        let brands = Set(backup.brands.map(\.id)), categories = Set(backup.categories.map(\.id))
        let coordinates = Set(backup.coordinates.map(\.id)), locations = Set(backup.locations.map(\.id))
        let items = Set(backup.items.map(\.id)), prices = Set(backup.prices.map(\.id)), logs = Set(backup.outfitLogs.map(\.id))
        guard backup.items.allSatisfy({ brands.contains($0.brandId) && categories.contains($0.categoryId)
            && ($0.coordinateId == nil || coordinates.contains($0.coordinateId!))
            && ($0.locationId == nil || locations.contains($0.locationId!)) }),
              backup.prices.allSatisfy({ items.contains($0.itemId) && $0.totalPrice.isFinite && $0.totalPrice >= 0
            && ($0.deposit == nil || ($0.deposit!.isFinite && $0.deposit! >= 0))
            && ($0.balance == nil || ($0.balance!.isFinite && $0.balance! >= 0)) }),
              backup.payments.allSatisfy({ prices.contains($0.priceId) && $0.amount.isFinite && $0.amount >= 0 }),
              backup.outfitItemCrossRefs.allSatisfy({ items.contains($0.itemId) && logs.contains($0.outfitLogId) }) else {
            throw ValidationError.invalid("备份包含无效关联或金额，无法恢复")
        }
        let associations = backup.outfitItemCrossRefs.map { "\($0.outfitLogId):\($0.itemId)" }
        guard Set(associations).count == associations.count else { throw ValidationError.invalid("备份包含重复穿搭关联") }
    }

    static func isRemoteImage(_ path: String) -> Bool {
        let url = URL(string: path)
        return ["http", "https"].contains(url?.scheme?.lowercased() ?? "") && url?.host != nil
    }

    private static func normalizedLegacyColors(_ value: Any?) -> Any {
        guard let value, !(value is NSNull) else { return [String]() }
        // Keep current arrays and the original iOS { "values": [...] } wrapper.
        guard let encoded = value as? String else { return value }
        let trimmed = encoded.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [String]() }
        if trimmed.hasPrefix("[") {
            let repaired = trimmed.replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\", with: "")
            for candidate in [trimmed, repaired] {
                if let colors = try? JSONDecoder().decode([String].self, from: Data(candidate.utf8)) {
                    return colors.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                }
            }
        }
        // Android ColorSelector accepts comma, ideographic comma and slash.
        return trimmed.components(separatedBy: CharacterSet(charactersIn: ",、/"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func restore(_ backup: BackupData) async throws {
        try await restore(backup, imageFiles: [:])
    }

    func restore(_ prepared: PreparedBackup) async throws {
        try await restore(prepared.backup, imageFiles: prepared.imageFiles)
    }

    private func restore(_ backup: BackupData, imageFiles: [String: URL]) async throws {
        try Self.validate(backup)
        let previous = try await snapshot()
        var pathMap: [String: String] = [:]
        var stagedPathMap: [URL: String] = [:]
        do {
            for original in backup.imagePaths {
                try Task.checkCancellation()
                let data: Data?
                if let source = imageFiles[original] {
                    if let reused = stagedPathMap[source] { pathMap[original] = reused; continue }
                    data = try Data(contentsOf: source, options: .mappedIfSafe)
                } else if let base64 = backup.imageData[original] {
                    guard let decoded = Data(base64Encoded: base64) else { throw ValidationError.invalid("备份图片编码无效") }
                    data = decoded
                } else { data = nil }
                if let data {
                    guard let path = ImageFileHelper.save(imageData: data) else { throw ValidationError.invalid("无法恢复备份图片") }
                    pathMap[original] = path
                    if let source = imageFiles[original] { stagedPathMap[source] = path }
                }
            }
            let mapping = pathMap
            try await queue.write { db in
                for table in ["outfitItemCrossRef", "payments", "prices", "items", "outfitLogs", "coordinates", "locations", "brands", "categories", "styles", "seasons", "sources"] {
                    try db.execute(sql: "DELETE FROM \(table)")
                }
                func image(_ path: String?) -> String? {
                    guard let path else { return nil }
                    if let mapped = mapping[path] { return mapped }
                    let url = ImageFileHelper.fileURL(for: path)
                    if !url.isFileURL { return path }
                    return ImageFileHelper.isOwnedFile(path) && FileManager.default.fileExists(atPath: url.path) ? path : nil
                }
                func images(_ values: StringList) -> StringList { StringList(values.values.compactMap { image($0) }) }
                for var value in backup.brands { value.logoUrl = image(value.logoUrl); try value.insert(db) }
                for var value in backup.categories { try value.insert(db) }
                for var value in backup.styles { try value.insert(db) }
                for var value in backup.seasons { try value.insert(db) }
                for var value in backup.sources { try value.insert(db) }
                for var value in backup.locations { value.imageUrl = image(value.imageUrl); try value.insert(db) }
                for var value in backup.coordinates { value.imageUrls = images(value.imageUrls); try value.insert(db) }
                for var value in backup.items { value.imageUrls = images(value.imageUrls); value.sizeChartImageUrl = image(value.sizeChartImageUrl); try value.insert(db) }
                for var value in backup.prices { try value.insert(db) }
                for var value in backup.payments {
                    // Calendar IDs and notification registrations belong to the originating device.
                    value.calendarEventId = nil; value.reminderSet = false
                    try value.insert(db)
                }
                for var value in backup.outfitLogs { value.imageUrls = images(value.imageUrls); try value.insert(db) }
                for value in backup.outfitItemCrossRefs { try value.insert(db) }
                for value in try Item.fetchAll(db) { try ItemRepository.refreshPaymentStatus(db, itemId: value.id) }
            }
        } catch {
            ImageFileHelper.delete(paths: Array(pathMap.values))
            throw error
        }
        try? ImageFileHelper.deleteUnreferenced(paths: Array(previous.imagePaths), db: queue)
    }

    /// Returns a disk-backed preview; the large image payload stays outside the
    /// JSON object and is never expanded into base64 for ZIP imports.
    static func prepare(at url: URL) throws -> PreparedBackup {
        let handle = try FileHandle(forReadingFrom: url)
        let magic = try handle.read(upToCount: 4) ?? Data()
        try handle.close()
        if magic.starts(with: [0x50, 0x4b]) { return try prepareZIP(at: url) }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 256 * 1024 * 1024 else { throw ValidationError.invalid("JSON 备份过大，请使用 ZIP 备份") }
        return PreparedBackup(backup: try preview(Data(contentsOf: url)))
    }

    private static func prepareZIP(at url: URL) throws -> PreparedBackup {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lolita-restore-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        do {
            let files = try ZipArchiveReader.extract(url, to: directory)
            guard let jsonURL = files["data.json"] else { throw ValidationError.invalid("ZIP 中缺少 data.json") }
            guard files.keys.allSatisfy({ $0 == "data.json" || $0 == "image_manifest.json" || validImageEntry($0) }) else {
                throw ValidationError.invalid("ZIP 包含不支持的内容，无法完整恢复")
            }
            let jsonSize = try jsonURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard jsonSize <= 32 * 1024 * 1024 else { throw ValidationError.invalid("备份数据列表过大") }
            let json = try Data(contentsOf: jsonURL)
            var backup = try preview(json)
            let images = Dictionary(uniqueKeysWithValues: files.compactMap { path, file in
                validImageEntry(path) ? (String(path.dropFirst("images/".count)), file) : nil
            })
            if let manifestURL = files["image_manifest.json"] {
                let manifestSize = try manifestURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard manifestSize <= 4 * 1024 * 1024 else { throw ValidationError.invalid("图片校验清单过大") }
                let manifest = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: manifestURL))
                guard Set(manifest.keys) == Set(images.keys) else { throw ValidationError.invalid("图片校验清单与 ZIP 内容不符") }
                for (name, file) in images {
                    guard manifest[name]?.lowercased() == (try sha256(file)) else {
                        throw ValidationError.invalid("备份图片校验失败，请重新导出")
                    }
                }
            } else {
                let root = try JSONSerialization.jsonObject(with: json) as? [String: Any]
                guard (root?["formatVersion"] as? Int ?? 1) < 2 else {
                    throw ValidationError.invalid("ZIP 缺少图片校验清单")
                }
            }
            var imageFiles: [String: URL] = [:]
            for path in backup.imagePaths where !isRemoteImage(path) {
                let name: String
                if path.hasPrefix("zip://images/") { name = String(path.dropFirst("zip://images/".count)) }
                else { name = URL(fileURLWithPath: path).lastPathComponent }
                guard validImageEntry("images/" + name), let file = images[name] else {
                    throw ValidationError.invalid("ZIP 缺少服饰引用的图片，请重新导出完整备份")
                }
                imageFiles[path] = file
            }
            // ZIP bytes take precedence over an optional legacy embedded map.
            backup.imageData = [:]
            return PreparedBackup(backup: backup, imageFiles: imageFiles, isZIP: true, stagingDirectory: directory)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private static func validImageEntry(_ path: String) -> Bool {
        guard path.hasPrefix("images/") else { return false }
        let name = String(path.dropFirst("images/".count))
        return !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\\")
    }

    private static func sha256(_ file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var digest = SHA256()
        while let bytes = try handle.read(upToCount: 64 * 1024), !bytes.isEmpty {
            try Task.checkCancellation()
            digest.update(data: bytes)
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    func exportZIP() async throws -> Data {
        let backup = try await snapshot()
        try Self.validate(backup)
        return try await Task.detached(priority: .userInitiated) { try Self.zip(backup) }.value
    }

    private static func zip(_ backup: BackupData) throws -> Data {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lolita-export-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archiveURL = directory.appendingPathComponent("backup.zip")
        let archive = try Archive(url: archiveURL, accessMode: .create)
        var names: [String: String] = [:]
        var manifest: [String: String] = [:]
        var stagedFiles: [String: URL] = [:]
        for path in backup.imagePaths.sorted() where !isRemoteImage(path) {
            guard ImageFileHelper.isOwnedFile(path) else {
                throw ValidationError.invalid("有本地图片缺失，无法创建完整 ZIP 备份")
            }
            let source = ImageFileHelper.fileURL(for: path)
            let nameHash = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
            let ext = source.pathExtension.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
            let name = nameHash + (ext.isEmpty ? "" : "." + ext)
            let staged = directory.appendingPathComponent(name)
            do { try FileManager.default.copyItem(at: source, to: staged) }
            catch { throw ValidationError.invalid("有本地图片缺失或不可读，无法创建完整 ZIP 备份") }
            names[path] = name
            stagedFiles[name] = staged
            manifest[name] = try sha256(staged)
        }
        var mapped = backup
        func image(_ value: String?) -> String? { value.map { names[$0].map { "zip://images/" + $0 } ?? $0 } }
        func images(_ values: StringList) -> StringList { StringList(values.values.compactMap(image)) }
        for index in mapped.brands.indices { mapped.brands[index].logoUrl = image(mapped.brands[index].logoUrl) }
        for index in mapped.locations.indices { mapped.locations[index].imageUrl = image(mapped.locations[index].imageUrl) }
        for index in mapped.items.indices {
            mapped.items[index].imageUrls = images(mapped.items[index].imageUrls)
            mapped.items[index].sizeChartImageUrl = image(mapped.items[index].sizeChartImageUrl)
        }
        for index in mapped.coordinates.indices { mapped.coordinates[index].imageUrls = images(mapped.coordinates[index].imageUrls) }
        for index in mapped.outfitLogs.indices { mapped.outfitLogs[index].imageUrls = images(mapped.outfitLogs[index].imageUrls) }
        mapped.imageData = [:]
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(mapped)) as! [String: Any]
        json.removeValue(forKey: "imageData")
        json["formatVersion"] = 1
        json["schemaVersion"] = 0
        func add(_ name: String, _ data: Data) throws {
            try archive.addEntry(with: name, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .deflate) {
                offset, size in data.subdata(in: Int(offset)..<min(Int(offset) + size, data.count))
            }
        }
        try add("data.json", JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]))
        for name in stagedFiles.keys.sorted() {
            try Task.checkCancellation()
            try archive.addEntry(with: "images/" + name, fileURL: stagedFiles[name]!, compressionMethod: .none)
        }
        try add("image_manifest.json", JSONEncoder().encode(manifest))
        return try Data(contentsOf: archiveURL, options: .mappedIfSafe)
    }

    /// Android's sectioned CSV format: every local entity has its own block,
    /// including empty tables, stable IDs and relationship columns.
    func exportCSV() async throws -> Data {
        let b = try await snapshot()
        func text(_ value: String?) -> String { value ?? "" }
        func number<T: CustomStringConvertible>(_ value: T?) -> String { value?.description ?? "" }
        func cell(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var sections: [String] = []
        func section(_ title: String, _ header: String, _ rows: [[String]]) {
            sections.append((["=== " + title + " ===", header] + rows.map { $0.map(cell).joined(separator: ",") }).joined(separator: "\r\n"))
        }
        section("BRANDS", "id,name,is_preset,logo_url,created_at", b.brands.map {
            [number($0.id), $0.name, number($0.isPreset), text($0.logoUrl), number($0.createdAt)]
        })
        section("CATEGORIES", "id,name,is_preset,created_at,category_group", b.categories.map {
            [number($0.id), $0.name, number($0.isPreset), number($0.createdAt), $0.group.rawValue]
        })
        section("ITEMS", "id,name,description,brand_id,category_id,coordinate_id,status,priority,image_urls,colors,season,style,size,size_chart_image_url,created_at,updated_at,location_id,source,coordinate_order,import_order_keys", b.items.map {
            [number($0.id), $0.name, $0.description, number($0.brandId), number($0.categoryId), number($0.coordinateId), $0.status.rawValue,
             $0.priority.rawValue, $0.imageUrls.values.joined(separator: ";"), $0.colors.values.joined(separator: ";"), text($0.season),
             text($0.style), text($0.size), text($0.sizeChartImageUrl), number($0.createdAt), number($0.updatedAt), number($0.locationId),
             text($0.source), number($0.coordinateOrder), $0.importOrderKeys?.values.joined(separator: ";") ?? ""]
        })
        section("COORDINATES", "id,name,description,image_urls,created_at,updated_at", b.coordinates.map {
            [number($0.id), $0.name, $0.description, $0.imageUrls.values.joined(separator: ";"), number($0.createdAt), number($0.updatedAt)]
        })
        section("STYLES", "id,name,is_preset,created_at", b.styles.map { [number($0.id), $0.name, number($0.isPreset), number($0.createdAt)] })
        section("SEASONS", "id,name,is_preset,created_at", b.seasons.map { [number($0.id), $0.name, number($0.isPreset), number($0.createdAt)] })
        section("LOCATIONS", "id,name,description,image_url,sort_order,created_at,updated_at", b.locations.map {
            [number($0.id), $0.name, $0.description, text($0.imageUrl), number($0.sortOrder), number($0.createdAt), number($0.updatedAt)]
        })
        section("SOURCES", "id,name,is_preset,created_at", b.sources.map { [number($0.id), $0.name, number($0.isPreset), number($0.createdAt)] })
        section("PRICES", "id,item_id,type,total_price,deposit,balance,created_at", b.prices.map {
            [number($0.id), number($0.itemId), $0.type.rawValue, number($0.totalPrice), number($0.deposit), number($0.balance), number($0.createdAt)]
        })
        section("PAYMENTS", "id,price_id,amount,due_date,is_paid,paid_date,reminder_set,custom_reminder_days,calendar_event_id,created_at", b.payments.map {
            [number($0.id), number($0.priceId), number($0.amount), number($0.dueDate), number($0.isPaid), number($0.paidDate),
             number($0.reminderSet), number($0.customReminderDays), number($0.calendarEventId), number($0.createdAt)]
        })
        section("OUTFIT_LOGS", "id,date,note,image_urls,created_at,updated_at", b.outfitLogs.map {
            [number($0.id), number($0.date), $0.note, $0.imageUrls.values.joined(separator: ";"), number($0.createdAt), number($0.updatedAt)]
        })
        section("OUTFIT_ITEM_CROSS_REFS", "outfit_log_id,item_id", b.outfitItemCrossRefs.map { [number($0.outfitLogId), number($0.itemId)] })
        return Data(("\u{feff}" + sections.joined(separator: "\r\n\r\n") + "\r\n").utf8)
    }
}
