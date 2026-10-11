import Foundation
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
                if table == "items" { result["colors"] = normalizedLegacyColors(result["colors"]) }
                return result
            }
        }
        if json["backupDate"] == nil { json["backupDate"] = now }
        if json["appVersion"] == nil { json["appVersion"] = "legacy" }
        if json["imageData"] == nil { json["imageData"] = [String: String]() }
        let backup = try JSONDecoder().decode(BackupData.self, from: JSONSerialization.data(withJSONObject: json))
        for table in [backup.brands.map(\.id), backup.categories.map(\.id), backup.items.map(\.id),
                      backup.coordinates.map(\.id), backup.outfitLogs.map(\.id), backup.prices.map(\.id),
                      backup.payments.map(\.id), backup.styles.map(\.id), backup.seasons.map(\.id),
                      backup.locations.map(\.id), backup.sources.map(\.id)] {
            guard table.allSatisfy({ $0 > 0 }), Set(table).count == table.count else {
                throw ValidationError.invalid("备份包含无效或重复的记录 ID")
            }
        }
        guard backup.prices.allSatisfy({ $0.totalPrice.isFinite && $0.totalPrice >= 0 }),
              backup.payments.allSatisfy({ $0.amount.isFinite && $0.amount >= 0 }) else {
            throw ValidationError.invalid("备份包含无效金额")
        }
        return backup
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
        let previous = try await snapshot()
        var pathMap: [String: String] = [:]
        do {
            for original in backup.imagePaths {
                if let base64 = backup.imageData[original] {
                    guard let data = Data(base64Encoded: base64), let path = ImageFileHelper.save(imageData: data) else {
                        throw ValidationError.invalid("无法恢复备份图片")
                    }
                    pathMap[original] = path
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

    func exportCSV() async throws -> Data {
        let backup = try await snapshot()
        func cell(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let brands = Dictionary(uniqueKeysWithValues: backup.brands.map { ($0.id, $0.name) })
        let categories = Dictionary(uniqueKeysWithValues: backup.categories.map { ($0.id, $0.name) })
        var rows = [["ID", "名称", "品牌", "分类", "状态", "优先级", "颜色", "季节", "风格", "尺码", "渠道", "描述", "总价"]]
        for item in backup.items {
            let price = backup.prices.filter { $0.itemId == item.id }.reduce(0) { $0 + $1.totalPrice }
            rows.append([String(item.id), item.name, brands[item.brandId] ?? "", categories[item.categoryId] ?? "", item.status.rawValue,
                         item.priority.rawValue, item.colors.values.joined(separator: ";"), item.season ?? "", item.style ?? "", item.size ?? "",
                         item.source ?? "", item.description, String(format: "%.2f", price)])
        }
        return Data(("\u{feff}" + rows.map { $0.map(cell).joined(separator: ",") }.joined(separator: "\r\n")).utf8)
    }
}
