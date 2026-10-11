import XCTest
import GRDB
import ZIPFoundation
import CryptoKit
@testable import lolita

final class BackupZIPRegressionTests: XCTestCase {
    private func zip(_ entries: [(String, Data)], compression: CompressionMethod = .deflate) throws -> Data {
        let archive = try Archive(accessMode: .create)
        for (path, content) in entries {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(content.count), compressionMethod: compression) {
                offset, size in content.subdata(in: Int(offset)..<min(Int(offset) + size, content.count))
            }
        }
        return try XCTUnwrap(archive.data)
    }

    private func file(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        try data.write(to: url)
        return url
    }

    private var androidJSON: Data {
        Data(#"{"brands":[{"id":1,"name":"品牌"}],"categories":[{"id":1,"name":"JSK"}],"items":[{"id":1,"name":"裙子","brandId":1,"categoryId":1,"imageUrls":["/data/user/0/com.lolita.app/files/images/photo.jpg"],"colors":"[\"白色\",\"粉色\"]"}],"coordinates":[],"prices":[],"payments":[],"outfitLogs":[],"outfitItemCrossRefs":[]}"#.utf8)
    }

    func testLegacyAndroidZIPPreviewsWithoutBase64AndRestoresPhoto() async throws {
        let photo = Data([1, 2, 3, 4, 5])
        let url = try file(zip([("data.json", androidJSON), ("images/photo.jpg", photo)]))
        defer { try? FileManager.default.removeItem(at: url) }
        let prepared = try BackupManager.prepare(at: url)
        XCTAssertTrue(prepared.isZIP)
        XCTAssertEqual(prepared.imageCount, 1)
        XCTAssertEqual(prepared.missingImageCount, 0)
        XCTAssertTrue(prepared.backup.imageData.isEmpty)
        XCTAssertEqual(prepared.backup.items.first?.colors.values, ["白色", "粉色"])
        let database = try LolitaDatabase(path: ":memory:")
        let manager = BackupManager(db: database.dbQueue)
        try await manager.restore(prepared)
        let restored = try await manager.snapshot()
        let path = try XCTUnwrap(restored.items.first?.imageUrls.values.first)
        defer { ImageFileHelper.delete(path: path) }
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), photo)
        XCTAssertNotEqual(path, prepared.backup.items.first?.imageUrls.values.first)
    }

    func testPreviewUsesStagedSnapshotAndCleansStagingOnRelease() throws {
        let original = Data([3, 6, 9])
        let url = try file(zip([("data.json", androidJSON), ("images/photo.jpg", original)]))
        defer { try? FileManager.default.removeItem(at: url) }
        var prepared: PreparedBackup? = try BackupManager.prepare(at: url)
        let staged = try XCTUnwrap(prepared?.imageFiles.values.first)
        try Data("document was replaced".utf8).write(to: url)
        XCTAssertEqual(try Data(contentsOf: staged), original)
        prepared = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path))
    }

    func testZIPRoundTripPreservesAllTablesAndClearsDeviceRegistrations() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        let photo = try XCTUnwrap(ImageFileHelper.save(imageData: Data([5, 4, 3, 2, 1])))
        defer { ImageFileHelper.delete(path: photo) }
        try await database.dbQueue.write { db in
            var brand = Brand(name: "品牌", logoUrl: photo); try brand.insert(db)
            var category = Category(name: "JSK"); try category.insert(db)
            var location = Location(name: "衣橱", imageUrl: photo); try location.insert(db)
            var coordinate = Coordinate(name: "套装", description: "", imageUrls: StringList([photo])); try coordinate.insert(db)
            var style = Style(name: "甜系"); try style.insert(db)
            var season = Season(name: "春"); try season.insert(db)
            var source = Source(name: "淘宝"); try source.insert(db)
            var item = Item(name: "裙子", brandId: brand.id, categoryId: category.id, status: .wished,
                            sizeChartImageUrl: photo, imageUrls: StringList([photo]), coordinateId: coordinate.id,
                            locationId: location.id, importOrderKeys: StringList(["tb:123", "tb:456"]))
            try item.insert(db)
            var price = Price(itemId: item.id, type: .depositBalance, totalPrice: 300, deposit: 100, balance: 200); try price.insert(db)
            var paid = Payment(priceId: price.id, amount: 100, dueDate: 1000, isPaid: true, paidDate: 1000,
                               calendarEventId: 123, reminderSet: true, customReminderDays: 3); try paid.insert(db)
            var balance = Payment(priceId: price.id, amount: 200, dueDate: 5000, reminderSet: true); try balance.insert(db)
            var log = OutfitLog(date: 2000, note: "日志", imageUrls: StringList([photo])); try log.insert(db)
            try OutfitItemCrossRef(outfitLogId: log.id, itemId: item.id).insert(db)
        }
        let manager = BackupManager(db: database.dbQueue)
        let original = try await manager.snapshot()
        let url = try file(await manager.exportZIP())
        defer { try? FileManager.default.removeItem(at: url) }
        let files = try ZipArchiveReader.read(Data(contentsOf: url))
        XCTAssertNotNil(files["image_manifest.json"])
        let prepared = try BackupManager.prepare(at: url)
        XCTAssertEqual(prepared.imageCount, 1)
        let target = try LolitaDatabase(path: ":memory:")
        let targetManager = BackupManager(db: target.dbQueue)
        try await targetManager.restore(prepared)
        let restored = try await targetManager.snapshot()
        defer { ImageFileHelper.delete(paths: Array(restored.imagePaths)) }
        XCTAssertEqual(restored.imagePaths.count, 1)
        XCTAssertEqual(restored.items.first?.status, .wished)
        XCTAssertEqual(restored.items.first?.importOrderKeys?.values, ["tb:123", "tb:456"])
        XCTAssertEqual(restored.items.first?.createdAt, original.items.first?.createdAt)
        XCTAssertEqual(restored.items.first?.updatedAt, original.items.first?.updatedAt)
        XCTAssertEqual(restored.items.first?.coordinateId, original.items.first?.coordinateId)
        XCTAssertEqual(restored.items.first?.locationId, original.items.first?.locationId)
        XCTAssertEqual(restored.styles.count, 1)
        XCTAssertEqual(restored.seasons.count, 1)
        XCTAssertEqual(restored.sources.count, 1)
        XCTAssertEqual(restored.prices.first?.totalPrice, 300)
        XCTAssertEqual(restored.payments.filter(\.isPaid).count, 1)
        XCTAssertEqual(restored.payments.first?.customReminderDays, 3)
        XCTAssertTrue(restored.payments.allSatisfy { $0.calendarEventId == nil && !$0.reminderSet })
        XCTAssertEqual(restored.outfitItemCrossRefs.first?.itemId, restored.items.first?.id)
    }

    func testDifferentLegacyPathsForSameArchiveImageKeepSharedReference() async throws {
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: androidJSON) as? [String: Any])
        root["brands"] = [["id": 1, "name": "品牌", "logoUrl": "zip://images/photo.jpg"]]
        let url = try file(zip([("data.json", JSONSerialization.data(withJSONObject: root)), ("images/photo.jpg", Data([1, 3, 5]))]))
        defer { try? FileManager.default.removeItem(at: url) }
        let prepared = try BackupManager.prepare(at: url)
        XCTAssertEqual(prepared.imageCount, 1)
        let database = try LolitaDatabase(path: ":memory:")
        let manager = BackupManager(db: database.dbQueue)
        try await manager.restore(prepared)
        let restored = try await manager.snapshot()
        defer { ImageFileHelper.delete(paths: Array(restored.imagePaths)) }
        XCTAssertEqual(restored.imagePaths.count, 1)
        XCTAssertEqual(restored.brands.first?.logoUrl, restored.items.first?.imageUrls.values.first)
    }

    func testLegacyPurchaseDateMigratesToPaidPaymentWithoutDuplicatingSchedule() throws {
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: androidJSON) as? [String: Any])
        root["prices"] = [["id": 7, "itemId": 1, "type": "FULL", "totalPrice": 250.0, "createdAt": 1000, "purchaseDate": 1200]]
        let migrated = try BackupManager.preview(JSONSerialization.data(withJSONObject: root))
        XCTAssertEqual(migrated.payments.count, 1)
        XCTAssertEqual(migrated.payments.first?.paidDate, 1200)
        XCTAssertEqual(migrated.payments.first?.amount, 250)
        XCTAssertEqual(migrated.payments.first?.isPaid, true)
        root["payments"] = [["id": 10, "priceId": 7, "amount": 250.0, "dueDate": 2000, "createdAt": 1000]]
        let retained = try BackupManager.preview(JSONSerialization.data(withJSONObject: root))
        XCTAssertEqual(retained.payments.count, 1)
        XCTAssertEqual(retained.payments.first?.id, 10)
        XCTAssertEqual(retained.payments.first?.dueDate, 2000)
    }

    func testZIPRejectsMissingImagesInvalidManifestAndFutureFormat() throws {
        let empty = try file(zip([("data.json", androidJSON)]))
        defer { try? FileManager.default.removeItem(at: empty) }
        XCTAssertThrowsError(try BackupManager.prepare(at: empty))
        let invalidManifest = Data(#"{"photo.jpg":"0000"}"#.utf8)
        let corrupt = try file(zip([("data.json", androidJSON), ("images/photo.jpg", Data([1])), ("image_manifest.json", invalidManifest)]))
        defer { try? FileManager.default.removeItem(at: corrupt) }
        XCTAssertThrowsError(try BackupManager.prepare(at: corrupt))
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: androidJSON) as? [String: Any])
        root["formatVersion"] = 99
        XCTAssertThrowsError(try BackupManager.preview(JSONSerialization.data(withJSONObject: root)))
    }

    func testRejectsIncompleteModernBackupAndUnsupportedNonemptyData() throws {
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: androidJSON) as? [String: Any])
        root["formatVersion"] = 2
        XCTAssertThrowsError(try BackupManager.preview(JSONSerialization.data(withJSONObject: root)))
        root["formatVersion"] = 1
        root["futureEntity"] = [["id": 1]]
        XCTAssertThrowsError(try BackupManager.preview(JSONSerialization.data(withJSONObject: root)))
        root.removeValue(forKey: "futureEntity")
        root["remoteItems"] = [["publicId": "cannot-drop-this-record"]]
        XCTAssertThrowsError(try BackupManager.preview(JSONSerialization.data(withJSONObject: root)))
        root["remoteItems"] = []
        XCTAssertEqual(try BackupManager.preview(JSONSerialization.data(withJSONObject: root)).items.count, 1)
    }

    func testZIPRejectsTraversalDuplicatesSymlinksCRCAndExpansionLimit() throws {
        for path in ["../escape", "/absolute", "images/../escape", "images/%2e%2e/escape", "images\\escape", "C:/file"] {
            XCTAssertThrowsError(try ZipArchiveReader.read(zip([(path, Data([1]))])))
        }
        XCTAssertThrowsError(try ZipArchiveReader.read(zip([("same", Data([1])), ("same", Data([2]))])))
        XCTAssertThrowsError(try ZipArchiveReader.read(zip([("same", Data([1])), ("SAME", Data([2]))])))
        XCTAssertThrowsError(try ZipArchiveReader.read(zip([("parent", Data([1])), ("parent/child", Data([2]))])))
        let linked = try Archive(accessMode: .create)
        let link = Data("/tmp/outside".utf8)
        try linked.addEntry(with: "images/link", type: .symlink, uncompressedSize: Int64(link.count)) { _, _ in link }
        XCTAssertThrowsError(try ZipArchiveReader.read(XCTUnwrap(linked.data)))
        let large = try zip([("large", Data(repeating: 0, count: 4096))])
        XCTAssertThrowsError(try ZipArchiveReader.read(large, maximumExpandedSize: 1024))
        var badCRC = try zip([("photo", Data([17, 23, 31, 47]))], compression: .none)
        let payload = try XCTUnwrap(badCRC.range(of: Data([17, 23, 31, 47])))
        badCRC[payload.lowerBound] = 99
        XCTAssertThrowsError(try ZipArchiveReader.read(badCRC))
    }

    func testRestoreTransactionFailurePreservesOriginalRowsAndImages() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        let image = try XCTUnwrap(ImageFileHelper.save(imageData: Data([7, 8, 9])))
        defer { ImageFileHelper.delete(path: image) }
        try await database.dbQueue.write { db in
            var brand = Brand(name: "原品牌", logoUrl: image); try brand.insert(db)
            var category = Category(name: "原分类"); try category.insert(db)
            var item = Item(name: "原服饰", brandId: brand.id, categoryId: category.id, imageUrls: StringList([image])); try item.insert(db)
        }
        let manager = BackupManager(db: database.dbQueue)
        let original = try await manager.snapshot()
        var invalid = original
        invalid.brands.append(Brand(id: 999, name: "原品牌"))
        invalid.imageData[image] = Data([2, 2, 2]).base64EncodedString()
        do { try await manager.restore(invalid); XCTFail("duplicate unique name must fail atomically") } catch { }
        let retained = try await manager.snapshot()
        XCTAssertEqual(retained.items.first?.name, "原服饰")
        XCTAssertEqual(retained.items.first?.imageUrls.values, [image])
        XCTAssertEqual(retained.brands.count, original.brands.count)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: image)), Data([7, 8, 9]))
    }

    func testAvailableAndroidBackupFixtureRestoresAllRecordsAnd190Images() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let fixture = root.deletingLastPathComponent().appendingPathComponent("lolita/lolita_backup_20260318_191642.zip")
        guard FileManager.default.fileExists(atPath: fixture.path) else { throw XCTSkip("Android backup fixture is local to the development checkout") }
        let prepared = try BackupManager.prepare(at: fixture)
        XCTAssertEqual(prepared.backup.items.count, 140)
        XCTAssertEqual(prepared.backup.coordinates.count, 27)
        XCTAssertEqual(prepared.backup.locations.count, 4)
        XCTAssertEqual(prepared.backup.outfitLogs.count, 3)
        XCTAssertEqual(prepared.backup.outfitItemCrossRefs.count, 6)
        XCTAssertEqual(prepared.backup.prices.count, 140)
        XCTAssertEqual(prepared.backup.payments.count, 144)
        XCTAssertEqual(prepared.imageCount, 190)
        XCTAssertEqual(prepared.missingImageCount, 0)
        let database = try LolitaDatabase(path: ":memory:")
        let manager = BackupManager(db: database.dbQueue)
        try await manager.restore(prepared)
        let restored = try await manager.snapshot()
        defer { ImageFileHelper.delete(paths: Array(restored.imagePaths)) }
        XCTAssertEqual(restored.imagePaths.count, 190)
        XCTAssertEqual(restored.items.count, 140)
        XCTAssertEqual(restored.payments.filter(\.isPaid).count, 133)
        XCTAssertTrue(restored.payments.allSatisfy { $0.calendarEventId == nil && !$0.reminderSet })
        let before = Dictionary(uniqueKeysWithValues: prepared.backup.items.map { ($0.id, $0) })
        for item in restored.items {
            let original = try XCTUnwrap(before[item.id])
            XCTAssertEqual(item.name, original.name)
            XCTAssertEqual(item.status, original.status)
            XCTAssertEqual(item.colors.values, original.colors.values)
            XCTAssertEqual(item.createdAt, original.createdAt)
            XCTAssertEqual(item.updatedAt, original.updatedAt)
            XCTAssertEqual(item.coordinateId, original.coordinateId)
            XCTAssertEqual(item.locationId, original.locationId)
        }
        func compare(_ original: String?, _ activated: String?) throws {
            guard let original, !original.isEmpty else { XCTAssertNil(activated); return }
            let activated = try XCTUnwrap(activated)
            if BackupManager.isRemoteImage(original) { XCTAssertEqual(original, activated); return }
            let staged = try XCTUnwrap(prepared.imageFiles[original])
            let expected = SHA256.hash(data: try Data(contentsOf: staged, options: .mappedIfSafe))
            let actual = SHA256.hash(data: try Data(contentsOf: URL(fileURLWithPath: activated), options: .mappedIfSafe))
            XCTAssertEqual(Data(expected), Data(actual))
        }
        for item in restored.items {
            let original = try XCTUnwrap(before[item.id])
            XCTAssertEqual(original.imageUrls.values.count, item.imageUrls.values.count)
            for (source, target) in Swift.zip(original.imageUrls.values, item.imageUrls.values) { try compare(source, target) }
            try compare(original.sizeChartImageUrl, item.sizeChartImageUrl)
        }
        let beforeCoordinates = Dictionary(uniqueKeysWithValues: prepared.backup.coordinates.map { ($0.id, $0) })
        for value in restored.coordinates {
            for (source, target) in Swift.zip(beforeCoordinates[value.id]!.imageUrls.values, value.imageUrls.values) { try compare(source, target) }
        }
        let beforeLogs = Dictionary(uniqueKeysWithValues: prepared.backup.outfitLogs.map { ($0.id, $0) })
        for value in restored.outfitLogs {
            for (source, target) in Swift.zip(beforeLogs[value.id]!.imageUrls.values, value.imageUrls.values) { try compare(source, target) }
        }
        let beforeLocations = Dictionary(uniqueKeysWithValues: prepared.backup.locations.map { ($0.id, $0) })
        for value in restored.locations { try compare(beforeLocations[value.id]?.imageUrl, value.imageUrl) }
        let beforeBrands = Dictionary(uniqueKeysWithValues: prepared.backup.brands.map { ($0.id, $0) })
        for value in restored.brands { try compare(beforeBrands[value.id]?.logoUrl, value.logoUrl) }
        let foreignKeys = try await database.dbQueue.read { try Row.fetchAll($0, sql: "PRAGMA foreign_key_check") }
        XCTAssertTrue(foreignKeys.isEmpty)
    }

    func testFullCSVIncludesAllLocalTablesRelationshipIDsAndEscapedText() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        try await database.dbQueue.write { db in
            var brand = Brand(name: "品牌,\"双引号\"\n换行"); try brand.insert(db)
            var category = Category(name: "JSK"); try category.insert(db)
            var item = Item(name: "裙子", brandId: brand.id, categoryId: category.id, importOrderKeys: StringList(["tb:100"])); try item.insert(db)
            var price = Price(itemId: item.id, type: .full, totalPrice: 123.5); try price.insert(db)
            var payment = Payment(priceId: price.id, amount: 123.5, dueDate: 1000); try payment.insert(db)
        }
        let csv = try await BackupManager(db: database.dbQueue).exportCSV()
        let text = try XCTUnwrap(String(data: csv, encoding: .utf8))
        XCTAssertTrue(csv.starts(with: [0xef, 0xbb, 0xbf]))
        for table in ["BRANDS", "CATEGORIES", "ITEMS", "COORDINATES", "STYLES", "SEASONS", "LOCATIONS", "SOURCES", "PRICES", "PAYMENTS", "OUTFIT_LOGS", "OUTFIT_ITEM_CROSS_REFS"] {
            XCTAssertTrue(text.contains("=== \(table) ==="), table)
        }
        XCTAssertTrue(text.contains("\"品牌,\"\"双引号\"\"\n换行\""))
        XCTAssertTrue(text.contains("id,price_id,amount,due_date,is_paid"))
        XCTAssertTrue(text.contains("\"123.5\""))
        XCTAssertTrue(text.contains("import_order_keys"))
        XCTAssertTrue(text.contains("\"tb:100\""))
    }
}
