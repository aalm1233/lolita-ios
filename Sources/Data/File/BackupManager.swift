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
    var orderBindings: [OrderBinding] = []
    var paymentStages: [PaymentStage] = []
    var iosLedgerVersion: Int? = nil
    var itemReferencePrices: [ItemReferencePrice] = []
    var orderRefunds: [OrderRefund] = []
    var orderCancellations: [OrderCancellation] = []
    var monthlyBudgets: [MonthlyBudget] = []
    var iosWardrobeVersion: Int? = nil
    var storageNodes: [StorageNode] = []
    var itemDrafts: [ItemDraft] = []

    var iosImportVersion: Int? = nil
    var orderImportSessions: [OrderImportSession] = []
    var orderImportFiles: [OrderImportFile] = []
    var orderImportRows: [OrderImportRow] = []
    var orderImportCommits: [OrderImportCommit] = []
    var orderImportReceipts: [OrderImportReceipt] = []
    var itemSourceRecords: [ItemSourceRecord] = []

    var imagePaths: Set<String> {
        var paths = Set(items.flatMap { $0.imageUrls.values })
        paths.formUnion(items.flatMap(\.detailImagePaths))
        paths.formUnion(storageNodes.compactMap(\.imageUrl))
        paths.formUnion(itemDrafts.flatMap(\.allImagePaths))
        paths.formUnion(orderImportRows.flatMap(\.allImagePaths))
        paths.formUnion(itemSourceRecords.flatMap { $0.imagePaths.values })
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
                       backupDate: Int64(Date().timeIntervalSince1970 * 1000), appVersion: "ios-2", imageData: [:],
                       orderBindings: try OrderBinding.fetchAll(db), paymentStages: try PaymentStage.fetchAll(db), iosLedgerVersion: 2,
                       itemReferencePrices: try ItemReferencePrice.fetchAll(db), orderRefunds: try OrderRefund.fetchAll(db),
                       orderCancellations: try OrderCancellation.fetchAll(db), monthlyBudgets: try MonthlyBudget.fetchAll(db),
                       iosWardrobeVersion: 1, storageNodes: try StorageNode.fetchAll(db), itemDrafts: try ItemDraft.fetchAll(db), iosImportVersion: 1,
                       orderImportSessions: try OrderImportSession.fetchAll(db), orderImportFiles: try OrderImportFile.fetchAll(db),
                       orderImportRows: try OrderImportRow.fetchAll(db), orderImportCommits: try OrderImportCommit.fetchAll(db),
                       orderImportReceipts: try OrderImportReceipt.fetchAll(db), itemSourceRecords: try ItemSourceRecord.fetchAll(db))
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
        let financeTables = ["itemReferencePrices", "orderRefunds", "orderCancellations", "monthlyBudgets"]
        let allowed = Set(tables + unsupportedTables + ["backupDate", "appVersion", "formatVersion", "schemaVersion", "imageData", "orderBindings", "paymentStages", "iosLedgerVersion"] + financeTables + ["iosWardrobeVersion", "storageNodes", "itemDrafts", "iosImportVersion"] + OrderImportMigration.tables)
        guard Set(json.keys).isSubset(of: allowed) else {
            throw ValidationError.invalid("备份包含未支持的数据类型，暂时无法完整恢复")
        }
        if let ledger = json["iosLedgerVersion"] {
            guard let number = ledger as? NSNumber, String(cString: number.objCType) != "c", [1, 2].contains(ledger as? Int ?? 0),
                  json["orderBindings"] is [[String: Any]], json["paymentStages"] is [[String: Any]] else {
                throw ValidationError.invalid("订单备份版本无效或缺少账本表")
            }
        } else {
            guard json["orderBindings"] == nil, json["paymentStages"] == nil else {
                throw ValidationError.invalid("订单备份缺少版本标识")
            }
            json["orderBindings"] = [[String: Any]](); json["paymentStages"] = [[String: Any]]()
        }
        if json["iosLedgerVersion"] as? Int == 2 {
            guard financeTables.allSatisfy({ json[$0] is [[String: Any]] }) else { throw ValidationError.invalid("售后预算备份缺少数据表") }
        } else {
            guard financeTables.allSatisfy({ json[$0] == nil }) else { throw ValidationError.invalid("售后预算备份缺少版本标识") }
            for table in financeTables { json[table] = [[String: Any]]() }
        }
        if let marker = json["iosImportVersion"] {
            guard let number = marker as? NSNumber, String(cString: number.objCType) != "c", number == 1,
                  OrderImportMigration.tables.allSatisfy({ json[$0] is [[String: Any]] }) else { throw ValidationError.invalid("导入会话备份版本无效或缺少数据表") }
        } else {
            guard OrderImportMigration.tables.allSatisfy({ json[$0] == nil }) else { throw ValidationError.invalid("导入会话备份缺少版本标识") }
            for table in OrderImportMigration.tables { json[table] = [[String: Any]]() }
        }
        if let wardrobe = json["iosWardrobeVersion"] {
            guard let number = wardrobe as? NSNumber, String(cString: number.objCType) != "c", number == 1,
                  json["storageNodes"] is [[String: Any]], json["itemDrafts"] is [[String: Any]] else {
                throw ValidationError.invalid("物品收纳备份版本无效或缺少数据表")
            }
        } else {
            guard json["storageNodes"] == nil, json["itemDrafts"] == nil else { throw ValidationError.invalid("物品收纳备份缺少版本标识") }
            json["storageNodes"] = [[String: Any]](); json["itemDrafts"] = [[String: Any]]()
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
            "items": ["description": "", "imageUrls": [String](), "colors": [String](), "status": "OWNED", "priority": "MEDIUM", "coordinateOrder": 0, "includedInParentPrice": false, "composition": "UNCONFIRMED", "specificationsJson": "", "sizeChartImageUrls": [String]()],
            "prices": ["shipping": 0, "purchaseRecordStatus": "NEEDS_REVIEW"], "payments": ["isPaid": false, "reminderSet": false], "outfitItemCrossRefs": [:]
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
                if table == "categories", row["categorySemantic"] == nil { result["categorySemantic"] = CategorySemantic.historical(row["name"] as? String ?? "").rawValue }
                if table == "items" { result["colors"] = normalizedLegacyColors(row["colors"] ?? row["color"]) }
                if row["updatedAt"] == nil, let createdAt = row["createdAt"] { result["updatedAt"] = createdAt }
                return result
            }
        }
        if version == 1 {
            var payments = json["payments"] as? [[String: Any]] ?? []
            var nextID = payments.compactMap { ($0["id"] as? NSNumber)?.int64Value }.max() ?? 0
            let prices = json["iosLedgerVersion"] == nil ? json["prices"] as? [[String: Any]] ?? [] : []
            for price in prices {
                guard let paidAt = price["purchaseDate"] as? Int64, let priceID = price["id"] as? Int64,
                      !payments.contains(where: { ($0["priceId"] as? Int64) == priceID }) else { continue }
                guard nextID < Int64.max else { throw ValidationError.invalid("备份付款记录 ID 超出范围") }
                nextID += 1
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
        guard backup.iosLedgerVersion == nil || backup.iosLedgerVersion == 1 || backup.iosLedgerVersion == 2 else { throw ValidationError.invalid("订单备份版本不受支持") }
        guard backup.iosLedgerVersion != nil || (backup.orderBindings.isEmpty && backup.paymentStages.isEmpty && backup.payments.allSatisfy { $0.stageId == nil }) else {
            throw ValidationError.invalid("订单备份缺少版本标识")
        }
        guard backup.iosLedgerVersion == 2 || (backup.itemReferencePrices.isEmpty && backup.orderRefunds.isEmpty && backup.orderCancellations.isEmpty && backup.monthlyBudgets.isEmpty) else {
            throw ValidationError.invalid("售后预算备份缺少版本标识")
        }
        guard backup.iosWardrobeVersion == nil || backup.iosWardrobeVersion == 1 else { throw ValidationError.invalid("物品收纳备份版本不受支持") }
        guard backup.iosWardrobeVersion != nil || (backup.storageNodes.isEmpty && backup.itemDrafts.isEmpty && backup.items.allSatisfy({ $0.storageNodeId == nil && $0.sizeChartImageUrls.values.isEmpty && $0.composition == .unconfirmed && $0.specificationsJson.isEmpty })) else { throw ValidationError.invalid("物品收纳备份缺少版本标识") }
        try ImportBackupValidation.validate(backup)
        try StorageTree.validate(backup.storageNodes, rooms: Set(backup.locations.map(\.id)))
        let storage = Dictionary(uniqueKeysWithValues: backup.storageNodes.map { ($0.id, $0) })
        for item in backup.items {
            _ = try WardrobeSpecifications.decode(item.specificationsJson)
            if let node = item.storageNodeId { guard storage[node]?.locationId == item.locationId else { throw ValidationError.invalid("物品收纳关联无效") } }
        }
        guard Set(backup.itemDrafts.map(\.id)).count == backup.itemDrafts.count,
              Set(backup.itemDrafts.compactMap(\.targetItemId)).count == backup.itemDrafts.compactMap(\.targetItemId).count else { throw ValidationError.invalid("草稿重复") }
        for draft in backup.itemDrafts {
            let item = try draft.item()
            guard !draft.id.isEmpty, draft.id.count <= 100, draft.updatedAt >= 0, draft.allImagePaths.allSatisfy({ !$0.isEmpty }),
                  draft.targetItemId == nil || backup.items.contains(where: { $0.id == draft.targetItemId }),
                  item.storageNodeId == nil || storage[item.storageNodeId!]?.locationId == item.locationId else { throw ValidationError.invalid("草稿关联或图片无效") }
        }
        for table in [backup.brands.map(\.id), backup.categories.map(\.id), backup.items.map(\.id),
                      backup.coordinates.map(\.id), backup.outfitLogs.map(\.id), backup.prices.map(\.id),
                      backup.payments.map(\.id), backup.styles.map(\.id), backup.seasons.map(\.id),
                      backup.locations.map(\.id), backup.sources.map(\.id), backup.paymentStages.map(\.id), backup.orderRefunds.map(\.id)] {
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
            && ($0.balance == nil || ($0.balance!.isFinite && $0.balance! >= 0)) && $0.shipping.isFinite && $0.shipping >= 0 }),
              backup.payments.allSatisfy({ prices.contains($0.priceId) && $0.amount.isFinite && $0.amount >= 0 }),
              backup.outfitItemCrossRefs.allSatisfy({ items.contains($0.itemId) && logs.contains($0.outfitLogId) }) else {
            throw ValidationError.invalid("备份包含无效关联或金额，无法恢复")
        }
        let associations = backup.outfitItemCrossRefs.map { "\($0.outfitLogId):\($0.itemId)" }
        guard Set(associations).count == associations.count else { throw ValidationError.invalid("备份包含重复穿搭关联") }
        let itemMap = Dictionary(uniqueKeysWithValues: backup.items.map { ($0.id, $0) })
        let priceMap = Dictionary(uniqueKeysWithValues: backup.prices.map { ($0.id, $0) })
        let stageMap = Dictionary(uniqueKeysWithValues: backup.paymentStages.map { ($0.id, $0) })
        guard backup.items.allSatisfy({ item in
            guard let parentId = item.parentItemId else { return !item.includedInParentPrice }
            guard parentId != item.id, let parent = itemMap[parentId], parent.parentItemId == nil else { return false }
            return !item.includedInParentPrice || !backup.prices.contains(where: { $0.itemId == item.id })
        }), backup.paymentStages.allSatisfy({ prices.contains($0.priceId) && $0.amount.isFinite && $0.amount >= 0
            && ($0.customReminderDays == nil || (0...365).contains($0.customReminderDays!)) }),
              backup.payments.allSatisfy({ $0.stageId == nil || stageMap[$0.stageId!]?.priceId == $0.priceId }),
              Set(backup.orderBindings.map(\.itemId)).count == backup.orderBindings.count,
              Set(backup.orderBindings.map(\.priceId)).count == backup.orderBindings.count,
              backup.orderBindings.allSatisfy({ itemMap[$0.itemId] != nil && priceMap[$0.priceId]?.itemId == $0.itemId
                  && priceMap[$0.priceId]?.purchaseRecordStatus == $0.purchaseRecordStatus && itemMap[$0.itemId]?.includedInParentPrice == false }),
              Set(backup.payments.compactMap(\.operationId)).count == backup.payments.compactMap(\.operationId).count else {
            throw ValidationError.invalid("备份中的主件、订单、阶段或付款关联无效")
        }
        guard Set(backup.itemReferencePrices.map(\.itemId)).count == backup.itemReferencePrices.count,
              Set(backup.orderCancellations.map(\.priceId)).count == backup.orderCancellations.count,
              Set(backup.monthlyBudgets.map(\.month)).count == backup.monthlyBudgets.count,
              Set(backup.orderRefunds.map(\.operationId)).count == backup.orderRefunds.count else {
            throw ValidationError.invalid("售后预算记录重复")
        }
        for reference in backup.itemReferencePrices {
            guard let item = itemMap[reference.itemId], !item.includedInParentPrice, reference.revision > 0 else { throw ValidationError.invalid("参考价关联无效") }
            try OrderAccounting.validate(reference.amount); _ = try AfterSaleRepository.note(reference.note)
        }
        for refund in backup.orderRefunds {
            guard prices.contains(refund.priceId), !refund.operationId.isEmpty, refund.operationId.count <= 100,
                  refund.receivedAt > 0, refund.voidedAt == nil || refund.voidedAt! > 0 else { throw ValidationError.invalid("退款关联或日期无效") }
            try OrderAccounting.validate(refund.amount, positive: true); _ = try AfterSaleRepository.note(refund.note)
        }
        for priceId in Set(backup.orderRefunds.map(\.priceId) + backup.orderCancellations.map(\.priceId)) {
            let refunded = try OrderAccounting.sum(backup.orderRefunds.filter { $0.priceId == priceId && $0.voidedAt == nil }.map(\.amount))
            let paid = try OrderAccounting.sum(backup.payments.filter { $0.priceId == priceId && $0.isPaid }.map(\.amount))
            guard try OrderAccounting.cents(refunded) <= OrderAccounting.cents(paid) else { throw ValidationError.invalid("备份退款超过原实付") }
            if let cancellation = backup.orderCancellations.first(where: { $0.priceId == priceId }) {
                guard prices.contains(priceId), cancellation.revision > 0, cancellation.cancelledAt > 0,
                      !backup.orderBindings.contains(where: { $0.priceId == priceId }) else { throw ValidationError.invalid("已取消订单不能绑定为当前订单") }
                if let expected = cancellation.expectedRefundTotal {
                    try OrderAccounting.validate(expected)
                    guard try OrderAccounting.cents(expected) >= 0,
                          try OrderAccounting.cents(expected) <= OrderAccounting.cents(paid) else { throw ValidationError.invalid("备份退款约定无效") }
                }
                _ = try AfterSaleRepository.note(cancellation.note)
            }
        }
        for budget in backup.monthlyBudgets {
            try FinanceRepository.validateMonth(budget.month)
            guard budget.amountCents >= 0, budget.amountCents < 9_000_000_000_000_000, budget.revision > 0 else { throw ValidationError.invalid("备份预算金额无效") }
        }
        for binding in backup.orderBindings {
            let price = priceMap[binding.priceId]!
            try OrderAccounting.validate(price.totalPrice, positive: true)
            try OrderAccounting.validate(price.shipping)
            guard price.shipping <= price.totalPrice else { throw ValidationError.invalid("备份中的邮费超过订单总额") }
            if binding.purchaseRecordStatus == .tracked {
                let actual = backup.payments.filter { $0.priceId == price.id && $0.isPaid }
                for payment in actual { try OrderAccounting.validate(payment.amount, positive: true) }
                guard try OrderAccounting.cents(OrderAccounting.sum(actual.map(\.amount))) <= OrderAccounting.cents(price.totalPrice) else {
                    throw ValidationError.invalid("备份中的实付超过订单总额")
                }
            }
        }
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
                try db.execute(sql: "UPDATE items SET parentItemId = NULL, includedInParentPrice = 0, storageNodeId = NULL")
                try db.execute(sql: "UPDATE storageNodes SET parentNodeId = NULL")
                for table in ["itemSourceRecords", "orderImportReceipts", "orderImportCommits", "orderImportRows", "orderImportFiles", "orderImportSessions", "itemDrafts", "orderRefunds", "orderCancellations", "itemReferencePrices", "monthlyBudgets", "orderBindings", "outfitItemCrossRef", "payments", "paymentStages", "prices", "items", "outfitLogs", "coordinates", "storageNodes", "locations", "brands", "categories", "styles", "seasons", "sources"] {
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
                for var value in backup.storageNodes.sorted(by: { ($0.parentNodeId == nil ? 0 : 1, $0.id) < ($1.parentNodeId == nil ? 0 : 1, $1.id) }) { value.imageUrl = image(value.imageUrl); try value.insert(db) }
                for var value in backup.coordinates { value.imageUrls = images(value.imageUrls); try value.insert(db) }
                for var value in backup.items.sorted(by: { ($0.parentItemId == nil ? 0 : 1, $0.id) < ($1.parentItemId == nil ? 0 : 1, $1.id) }) { value.imageUrls = images(value.imageUrls); value.sizeChartImageUrl = image(value.sizeChartImageUrl); value.sizeChartImageUrls = images(value.sizeChartImageUrls); try value.insert(db) }
                for var value in backup.itemDrafts { value.imagePaths = images(value.imagePaths); value.detailImagePaths = images(value.detailImagePaths); try value.insert(db) }
                for value in backup.orderImportSessions { try value.insert(db) }
                for value in backup.orderImportFiles { try value.insert(db) }
                for var value in backup.orderImportRows { value.imagePaths = images(value.imagePaths); value.detailImagePaths = images(value.detailImagePaths); try value.insert(db) }
                for value in backup.orderImportCommits { try value.insert(db) }
                for value in backup.orderImportReceipts { try value.insert(db) }
                for var value in backup.itemSourceRecords { value.imagePaths = images(value.imagePaths); try value.insert(db) }
                for var value in backup.prices { try value.insert(db) }
                for var value in backup.paymentStages { value.reminderSet = false; try value.insert(db) }
                for var value in backup.payments {
                    // Calendar IDs and notification registrations belong to the originating device.
                    value.calendarEventId = nil; value.reminderSet = false
                    try value.insert(db)
                }
                for value in backup.itemReferencePrices { try value.insert(db) }
                for var value in backup.orderRefunds { try value.insert(db) }
                for value in backup.orderCancellations { try value.insert(db) }
                for value in backup.monthlyBudgets { try value.insert(db) }
                for var value in backup.outfitLogs { value.imageUrls = images(value.imageUrls); try value.insert(db) }
                for value in backup.outfitItemCrossRefs { try value.insert(db) }
                if backup.iosLedgerVersion == nil { try OrderMigration.backfill(db) }
                else { for value in backup.orderBindings { try value.insert(db) } }
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
        for index in mapped.storageNodes.indices { mapped.storageNodes[index].imageUrl = image(mapped.storageNodes[index].imageUrl) }
        for index in mapped.orderImportRows.indices {
            mapped.orderImportRows[index].imagePaths = images(mapped.orderImportRows[index].imagePaths)
            mapped.orderImportRows[index].detailImagePaths = images(mapped.orderImportRows[index].detailImagePaths)
        }
        for index in mapped.itemSourceRecords.indices { mapped.itemSourceRecords[index].imagePaths = images(mapped.itemSourceRecords[index].imagePaths) }
        for index in mapped.itemDrafts.indices {
            mapped.itemDrafts[index].imagePaths = images(mapped.itemDrafts[index].imagePaths)
            mapped.itemDrafts[index].detailImagePaths = images(mapped.itemDrafts[index].detailImagePaths)
        }
        for index in mapped.items.indices {
            mapped.items[index].imageUrls = images(mapped.items[index].imageUrls)
            mapped.items[index].sizeChartImageUrl = image(mapped.items[index].sizeChartImageUrl)
            mapped.items[index].sizeChartImageUrls = images(mapped.items[index].sizeChartImageUrls)
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
        section("CATEGORIES", "id,name,is_preset,created_at,category_group,category_semantic", b.categories.map {
            [number($0.id), $0.name, number($0.isPreset), number($0.createdAt), $0.group.rawValue, $0.categorySemantic.rawValue]
        })
        section("ITEMS", "id,name,description,brand_id,category_id,coordinate_id,status,priority,image_urls,colors,season,style,size,size_chart_image_url,created_at,updated_at,location_id,source,coordinate_order,import_order_keys,parent_item_id,included_in_parent_price,composition,specifications_json,size_chart_image_urls,storage_node_id", b.items.map {
            [number($0.id), $0.name, $0.description, number($0.brandId), number($0.categoryId), number($0.coordinateId), $0.status.rawValue,
             $0.priority.rawValue, $0.imageUrls.values.joined(separator: ";"), $0.colors.values.joined(separator: ";"), text($0.season),
             text($0.style), text($0.size), text($0.sizeChartImageUrl), number($0.createdAt), number($0.updatedAt), number($0.locationId),
             text($0.source), number($0.coordinateOrder), $0.importOrderKeys?.values.joined(separator: ";") ?? "", number($0.parentItemId), number($0.includedInParentPrice), $0.composition.rawValue, $0.specificationsJson, $0.sizeChartImageUrls.values.joined(separator: ";"), number($0.storageNodeId)]
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
        section("PRICES", "id,item_id,type,total_price,deposit,balance,created_at,shipping,purchase_record_status", b.prices.map {
            [number($0.id), number($0.itemId), $0.type.rawValue, number($0.totalPrice), number($0.deposit), number($0.balance), number($0.createdAt), number($0.shipping), $0.purchaseRecordStatus.rawValue]
        })
        section("PAYMENTS", "id,price_id,amount,due_date,is_paid,paid_date,reminder_set,custom_reminder_days,calendar_event_id,created_at,stage_id,operation_id", b.payments.map {
            [number($0.id), number($0.priceId), number($0.amount), number($0.dueDate), number($0.isPaid), number($0.paidDate),
             number($0.reminderSet), number($0.customReminderDays), number($0.calendarEventId), number($0.createdAt), number($0.stageId), text($0.operationId)]
        })
        section("ORDER_BINDINGS", "item_id,price_id,purchase_record_status", b.orderBindings.map {
            [number($0.itemId), number($0.priceId), $0.purchaseRecordStatus.rawValue]
        })
        section("PAYMENT_STAGES", "id,price_id,name,amount,due_date,reminder_set,custom_reminder_days", b.paymentStages.map {
            [number($0.id), number($0.priceId), $0.name, number($0.amount), number($0.dueDate), number($0.reminderSet), number($0.customReminderDays)]
        })
        section("OUTFIT_LOGS", "id,date,note,image_urls,created_at,updated_at", b.outfitLogs.map {
            [number($0.id), number($0.date), $0.note, $0.imageUrls.values.joined(separator: ";"), number($0.createdAt), number($0.updatedAt)]
        })
        section("OUTFIT_ITEM_CROSS_REFS", "outfit_log_id,item_id", b.outfitItemCrossRefs.map { [number($0.outfitLogId), number($0.itemId)] })
        section("ITEM_REFERENCE_PRICES", "item_id,amount,note,revision,updated_at", b.itemReferencePrices.map {
            [number($0.itemId), number($0.amount), $0.note, number($0.revision), number($0.updatedAt)]
        })
        section("ORDER_REFUNDS", "id,price_id,amount,kind,received_at,note,operation_id,created_at,voided_at", b.orderRefunds.map {
            [number($0.id), number($0.priceId), number($0.amount), $0.kind.rawValue, number($0.receivedAt), $0.note, $0.operationId, number($0.createdAt), number($0.voidedAt)]
        })
        section("ORDER_CANCELLATIONS", "price_id,expected_refund_total,cancelled_at,note,revision", b.orderCancellations.map {
            [number($0.priceId), number($0.expectedRefundTotal), number($0.cancelledAt), $0.note, number($0.revision)]
        })
        section("MONTHLY_BUDGETS", "month,amount_cents,revision", b.monthlyBudgets.map { [$0.month, number($0.amountCents), number($0.revision)] })
        section("STORAGE_NODES", "id,location_id,parent_node_id,name,description,image_url,sort_order,created_at,updated_at", b.storageNodes.map {
            [number($0.id), number($0.locationId), number($0.parentNodeId), $0.name, $0.description, text($0.imageUrl), number($0.sortOrder), number($0.createdAt), number($0.updatedAt)]
        })
        section("ITEM_DRAFTS", "id,target_item_id,data_json,image_paths,detail_image_paths,baseline_updated_at,updated_at", b.itemDrafts.map {
            [$0.id, number($0.targetItemId), $0.dataJson, $0.imagePaths.values.joined(separator: ";"), $0.detailImagePaths.values.joined(separator: ";"), number($0.baselineUpdatedAt), number($0.updatedAt)]
        })
        section("ORDER_IMPORT_SESSIONS", "id,revision,kind,data_json,pending_operation_id,created_at,updated_at", b.orderImportSessions.map { [$0.id, number($0.revision), $0.kind, $0.dataJson, text($0.pendingOperationId), number($0.createdAt), number($0.updatedAt)] })
        section("ORDER_IMPORT_FILES", "id,session_id,name,sha256,data_json,problem", b.orderImportFiles.map { [$0.id, $0.sessionId, $0.name, $0.sha256, $0.dataJson, text($0.problem)] })
        section("ORDER_IMPORT_ROWS", "id,session_id,position,source_key,data_json,image_paths,detail_image_paths", b.orderImportRows.map { [$0.id, $0.sessionId, number($0.position), $0.sourceKey, $0.dataJson, $0.imagePaths.values.joined(separator: ";"), $0.detailImagePaths.values.joined(separator: ";")] })
        section("ORDER_IMPORT_COMMITS", "id,session_id,revision,snapshot_hash,result_json,created_at", b.orderImportCommits.map { [$0.id, text($0.sessionId), number($0.revision), $0.snapshotHash, $0.resultJson, number($0.createdAt)] })
        section("ORDER_IMPORT_RECEIPTS", "id,source_key,generation,order_id,source_snapshot,commit_id,item_id,paid_cents,shipping_cents,created_at", b.orderImportReceipts.map { [$0.id, $0.sourceKey, number($0.generation), $0.orderId, $0.sourceSnapshot, $0.commitId, number($0.itemId), number($0.paidCents), number($0.shippingCents), number($0.createdAt)] })
        section("ITEM_SOURCE_RECORDS", "id,item_id,kind,public_url,snapshot_json,applied_fields,image_paths,created_at", b.itemSourceRecords.map { [$0.id, number($0.itemId), $0.kind, text($0.publicUrl), $0.snapshotJson, $0.appliedFields.values.joined(separator: ";"), $0.imagePaths.values.joined(separator: ";"), number($0.createdAt)] })
        return Data(("\u{feff}" + sections.joined(separator: "\r\n\r\n") + "\r\n").utf8)
    }
}
