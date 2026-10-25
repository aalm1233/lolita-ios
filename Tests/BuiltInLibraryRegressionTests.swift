import XCTest
import GRDB
import CryptoKit
import ImageIO
@testable import lolita

final class BuiltInLibraryRegressionTests: XCTestCase {
    private func fixture() throws -> (DatabaseQueue, UserDefaults, URL) {
        let q = try LolitaDatabase(path: ":memory:").dbQueue
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (q, defaults, directory)
    }
    func testOriginalAssetsAndTemplatesHaveValidImagesAndRecordedHashes() throws {
        struct Manifest: Decodable { let assets: [String: String]; let presetBrands: Int }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: BuiltInLibrary.assetURL("builtin/source-manifest.json")))
        XCTAssertEqual(manifest.presetBrands, PresetData.brands.count)
        XCTAssertEqual(manifest.assets.count, 26)
        for (path, hash) in manifest.assets {
            let data = try Data(contentsOf: BuiltInLibrary.assetURL("builtin/" + path))
            XCTAssertEqual(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), hash)
            if !path.hasSuffix("json") {
                let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
                XCTAssertNotNil(CGImageSourceCreateImageAtIndex(source, 0, nil), path)
            }
        }
        XCTAssertEqual(try BuiltInLibrary.templates().count, 4)
        XCTAssertThrowsError(try BuiltInLibrary.assetURL("builtin/../Info.plist"))
        XCTAssertTrue(CategorySemantic.allCases.filter { $0 != .unconfirmed }.allSatisfy { type in PresetData.categories.contains { $0.name == type.label } })
    }
    func testFreshInitializationAndUserDeletionStayDeletedOnRestart() throws {
        let (q, defaults, dir) = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
        try BuiltInLibrary.initialize(db: q, defaults: defaults, imagesDirectory: dir)
        XCTAssertTrue(defaults.bool(forKey: BuiltInLibrary.initializedKey))
        try q.write { db in
            XCTAssertEqual(try Brand.fetchCount(db), 201)
            XCTAssertEqual(try Location.fetchCount(db), 6)
            XCTAssertEqual(try StorageNode.fetchCount(db), 0, "Reading templates must not create storage nodes")
            XCTAssertTrue(try Location.fetchAll(db).allSatisfy { $0.id > 0 && $0.imageUrl != nil })
            try db.execute(sql: "DELETE FROM locations WHERE name = '卧室'")
            try db.execute(sql: "UPDATE brands SET logoUrl = NULL WHERE name = '花与珍珠匣'")
            try db.execute(sql: "DELETE FROM brands WHERE name = 'Atelier Boz'")
        }
        try BuiltInLibrary.initialize(db: q, defaults: defaults, imagesDirectory: dir)
        try q.read { db in
            XCTAssertNil(try Location.filter(Column("name") == "卧室").fetchOne(db))
            XCTAssertNil(try Brand.filter(Column("name") == "Atelier Boz").fetchOne(db))
            XCTAssertNil(try Brand.filter(Column("name") == "花与珍珠匣").fetchOne(db)?.logoUrl)
        }
    }
    func testUpgradeOnlyFillsMissingImagesAndKeepsOriginalIdentityAndBusinessValues() throws {
        let (q, defaults, dir) = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
        let old = try BuiltInLibrary.copyImage("builtin/brands/zjstory.jpg", imagesDirectory: dir)
        let original = try Data(contentsOf: URL(fileURLWithPath: old))
        try q.write { db in
            var bedroom = Location(id: 41, name: "卧室", description: "我自己的房间", imageUrl: old, sortOrder: 91, createdAt: 12, updatedAt: 13); try bedroom.insert(db)
            var study = Location(id: 42, name: "书房", description: "旧描述", sortOrder: 92, createdAt: 14, updatedAt: 15); try study.insert(db)
            var brand = Brand(id: 61, name: "Elpress L", isPreset: false, logoUrl: old, createdAt: 16); try brand.insert(db)
            var category = Category(id: 71, name: "JSK", group: .accessory, isPreset: false, createdAt: 17); category.categorySemantic = .unconfirmed; try category.insert(db)
            var item = Item(name: "旧衣服", brandId: 61, categoryId: 71, imageUrls: StringList([old]), locationId: 41); try item.insert(db)
        }
        let before = try q.read { db in try Row.fetchAll(db, sql: "SELECT * FROM items") }
        try BuiltInLibrary.initialize(db: q, defaults: defaults, imagesDirectory: dir)
        try q.read { db in
            let bedroom = try XCTUnwrap(Location.fetchOne(db, key: 41)), study = try XCTUnwrap(Location.fetchOne(db, key: 42))
            XCTAssertEqual(bedroom.imageUrl, old); XCTAssertEqual(bedroom.description, "我自己的房间"); XCTAssertEqual(bedroom.updatedAt, 13)
            XCTAssertNotNil(study.imageUrl); XCTAssertEqual(study.description, "旧描述"); XCTAssertEqual(study.sortOrder, 92); XCTAssertEqual(study.updatedAt, 15)
            XCTAssertEqual(try Brand.fetchOne(db, key: 61)?.logoUrl, old)
            XCTAssertEqual(try Category.fetchOne(db, key: 71)?.categorySemantic, .unconfirmed)
            XCTAssertEqual(try Category.fetchOne(db, key: 71)?.group, .accessory)
            XCTAssertEqual(try Row.fetchAll(db, sql: "SELECT * FROM items"), before)
            XCTAssertEqual(try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").count, 0)
        }
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: old)), original)
    }
    func testInitializationFailureRollsBackRowsAndRemovesOnlyUncommittedImagesThenCanRetry() throws {
        let (q, defaults, dir) = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
        try q.write { db in try db.execute(sql: "CREATE TRIGGER reject_logo BEFORE UPDATE OF logoUrl ON brands BEGIN SELECT RAISE(ABORT, 'test'); END") }
        XCTAssertThrowsError(try BuiltInLibrary.initialize(db: q, defaults: defaults, imagesDirectory: dir))
        XCTAssertFalse(defaults.bool(forKey: BuiltInLibrary.initializedKey))
        XCTAssertEqual(try q.read { try Location.fetchCount($0) }, 0)
        XCTAssertEqual(try q.read { try Brand.fetchCount($0) }, 0)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
        try q.write { try $0.execute(sql: "DROP TRIGGER reject_logo") }
        try BuiltInLibrary.initialize(db: q, defaults: defaults, imagesDirectory: dir)
        XCTAssertTrue(defaults.bool(forKey: BuiltInLibrary.initializedKey))
    }
    func testAdoptionIsAtomicOnDuplicateAndKeepsPreviousImages() throws {
        let (q, defaults, dir) = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
        try BuiltInLibrary.initialize(db: q, defaults: defaults, imagesDirectory: dir)
        let room = try XCTUnwrap(q.read { try Location.fetchOne($0) })
        try BuiltInLibrary.adoptTemplates(["shoe_cabinet"], roomId: room.id, db: q, imagesDirectory: dir)
        let before = Set(try FileManager.default.contentsOfDirectory(atPath: dir.path))
        XCTAssertThrowsError(try BuiltInLibrary.adoptTemplates(["wig_stand", "shoe_cabinet"], roomId: room.id, db: q, imagesDirectory: dir))
        XCTAssertEqual(try q.read { try StorageNode.fetchCount($0) }, 1)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: dir.path)), before)
        try BuiltInLibrary.adoptTemplates(["wig_stand", "sock_drawer", "accessory_box"], roomId: room.id, db: q, imagesDirectory: dir)
        XCTAssertEqual(try q.read { try StorageNode.fetchCount($0) }, 4)
        XCTAssertThrowsError(try BuiltInLibrary.adoptTemplates(["unknown"], roomId: room.id, db: q, imagesDirectory: dir))
        XCTAssertThrowsError(try BuiltInLibrary.adoptTemplates(["wig_stand"], roomId: -1, db: q, imagesDirectory: dir))
    }
    func testBrandAliasesGetIndependentOwnedImagesAndNeverReplaceProvidedImages() throws {
        let (_, _, dir) = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
        let first = try BuiltInLibrary.prepareNewBrand(Brand(name: " Elpress L "), imagesDirectory: dir)
        let second = try BuiltInLibrary.prepareNewBrand(Brand(name: "ELPRESS"), imagesDirectory: dir)
        XCTAssertNotEqual(first.logoUrl, second.logoUrl)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: XCTUnwrap(first.logoUrl))), try Data(contentsOf: URL(fileURLWithPath: XCTUnwrap(second.logoUrl))))
        XCTAssertEqual(try BuiltInLibrary.prepareNewBrand(Brand(name: "Elpress", logoUrl: "custom"), imagesDirectory: dir).logoUrl, "custom")
        XCTAssertNil(try BuiltInLibrary.prepareNewBrand(Brand(name: "自定义品牌"), imagesDirectory: dir).logoUrl)
    }
    @MainActor
    func testUnrelatedLegacyDraftRemainsByteExactDuringPresetStorageMoveAndDeletion() async throws {
        let (q, defaults, dir) = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
        try await q.write { db in
            var room = Location(name: "旧房间"); try room.insert(db)
            var brand = Brand(name: "自定义旧品牌"); try brand.insert(db)
            var category = Category(name: "自定义旧分类"); try category.insert(db)
            var item = Item(name: "旧草稿服饰", brandId: brand.id, categoryId: category.id, locationId: room.id)
            item.specificationsJson = "legacy-unparsed-specifications"
            try item.insert(db)
            let draft = try ItemDraft.make(id: "legacy-draft", item: item, baseline: 17)
            try draft.insert(db)
        }
        let original = try await q.read { try ItemDraft.fetchOne($0, key: "legacy-draft") }
        let old = try XCTUnwrap(original)
        XCTAssertThrowsError(try old.item())
        try BuiltInLibrary.initialize(db: q, defaults: defaults, imagesDirectory: dir)
        let rooms = try await q.read { try Location.fetchAll($0) }
        let bedroom = try XCTUnwrap(rooms.first { $0.name == "卧室" })
        let living = try XCTUnwrap(rooms.first { $0.name == "客厅" })
        let storage = try XCTUnwrap(rooms.first { $0.name == "储物间" })
        try BuiltInLibrary.adoptTemplates(["wig_stand"], roomId: bedroom.id, db: q, imagesDirectory: dir)
        let loaded = try await q.read { try StorageNode.fetchOne($0) }
        let node = try XCTUnwrap(loaded), repository = StorageRepository(db: q)
        try await repository.move(nodeId: node.id, roomId: living.id, parentId: nil)
        try await repository.delete(nodeId: node.id)
        try await repository.deleteRoom(storage)
        let after = try await q.read { try ItemDraft.fetchOne($0, key: "legacy-draft") }
        let kept = try XCTUnwrap(after)
        XCTAssertEqual(kept.dataJson, old.dataJson)
        XCTAssertEqual(kept.imagePaths.values, old.imagePaths.values)
        XCTAssertEqual(kept.detailImagePaths.values, old.detailImagePaths.values)
        XCTAssertEqual(kept.baselineUpdatedAt, old.baselineUpdatedAt)
        XCTAssertEqual(kept.updatedAt, old.updatedAt)
        try BuiltInLibrary.initialize(db: q, defaults: defaults, imagesDirectory: dir)
        let deleted = try await q.read { try Location.fetchOne($0, key: storage.id) }
        XCTAssertNil(deleted)
    }
    @MainActor
    func testBuiltInRoomsBrandsAndAdoptedStorageRoundTripThroughZIP() async throws {
        let q = try LolitaDatabase(path: ":memory:").dbQueue
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        try BuiltInLibrary.initialize(db: q, defaults: defaults)
        let loadedRoom = try await q.read { try Location.fetchOne($0) }
        let room = try XCTUnwrap(loadedRoom)
        try BuiltInLibrary.adoptTemplates(["wig_stand", "sock_drawer"], roomId: room.id, db: q)
        let originalPaths = try await q.read { db in try Location.fetchAll(db).compactMap(\.imageUrl) + Brand.fetchAll(db).compactMap(\.logoUrl) + StorageNode.fetchAll(db).compactMap(\.imageUrl) }
        defer { ImageFileHelper.delete(paths: originalPaths) }
        let bytes = try await BackupManager(db: q).exportZIP()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        try bytes.write(to: url); defer { try? FileManager.default.removeItem(at: url) }
        let prepared = try BackupManager.prepare(at: url)
        let target = try LolitaDatabase(path: ":memory:").dbQueue
        try await BackupManager(db: target).restore(prepared)
        let restoredPaths = try await target.read { db in try Location.fetchAll(db).compactMap(\.imageUrl) + Brand.fetchAll(db).compactMap(\.logoUrl) + StorageNode.fetchAll(db).compactMap(\.imageUrl) }
        defer { ImageFileHelper.delete(paths: restoredPaths) }
        XCTAssertEqual(restoredPaths.count, originalPaths.count)
        for (a, b) in zip(originalPaths, restoredPaths) { XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: a)), try Data(contentsOf: ImageFileHelper.fileURL(for: b))) }
        let counts = try await target.read { (try Location.fetchCount($0), try StorageNode.fetchCount($0)) }
        XCTAssertEqual(counts.0, 6)
        XCTAssertEqual(counts.1, 2)
    }
}
