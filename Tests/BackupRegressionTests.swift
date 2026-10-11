import XCTest
import GRDB
@testable import lolita

final class BackupRegressionTests: XCTestCase {
    func testAndroidLegacyJSONDefaultsAndArrayCompatibility() throws {
        let data = Data(#"{"brands":[{"id":1,"name":"品牌"}],"categories":[{"id":1,"name":"JSK"}],"items":[{"id":1,"name":"裙子","brandId":1,"categoryId":1,"imageUrls":["/android/photo.jpg"],"colors":["白色"]}]}"#.utf8)
        let backup = try BackupManager.preview(data)
        XCTAssertEqual(backup.items.first?.colors.values, ["白色"])
        XCTAssertEqual(backup.categories.first?.group, .clothing)
        XCTAssertEqual(backup.missingImageCount, 1)
        XCTAssertTrue(backup.outfitLogs.isEmpty)
        XCTAssertTrue(backup.sources.isEmpty)
    }

    func testLegacyAndroidColorsRestoreAndExportAsArrays() async throws {
        let colors: [Any] = [
            #"["白色","粉色"]"#, NSNull(), "", " \n ",
            "红色, 白色、蓝色 / 黑色,,/ ", "水色",
            ["金色", "银色"], ["values": ["棕色", "米色"]],
            #"[\"紫色\",\"黑色\"]"#
        ]
        let expected = [
            ["白色", "粉色"], [], [], [],
            ["红色", "白色", "蓝色", "黑色"], ["水色"],
            ["金色", "银色"], ["棕色", "米色"], ["紫色", "黑色"]
        ]
        let rows = colors.enumerated().map { index, value -> [String: Any] in
            ["id": index + 1, "name": "测试服饰\(index + 1)", "brandId": 1, "categoryId": 1, "colors": value]
        }
        let json: [String: Any] = [
            "brands": [["id": 1, "name": "品牌"]],
            "categories": [["id": 1, "name": "JSK"]],
            "items": rows
        ]
        let preview = try BackupManager.preview(JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(preview.items.map { $0.colors.values }, expected)

        let database = try LolitaDatabase(path: ":memory:")
        let manager = BackupManager(db: database.dbQueue)
        try await manager.restore(preview)
        let restored = try await manager.snapshot()
        let valuesByID = Dictionary(uniqueKeysWithValues: restored.items.map { ($0.id, $0.colors.values) })
        for (index, values) in expected.enumerated() {
            XCTAssertEqual(valuesByID[Int64(index + 1)], values)
        }
        let exported = try await manager.exportJSON()
        let exportJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: exported) as? [String: Any])
        let exportedItems = try XCTUnwrap(exportJSON["items"] as? [[String: Any]])
        XCTAssertTrue(exportedItems.allSatisfy { $0["colors"] is [String] })
        XCTAssertEqual(try BackupManager.preview(exported).items.count, expected.count)
    }

    func testRestoreBadForeignKeyPreservesExistingDatabase() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        try await database.dbQueue.write { try PresetData.seed($0) }
        let manager = BackupManager(db: database.dbQueue)
        let original = try await manager.snapshot()
        var invalid = original
        invalid.items = [Item(id: 1, name: "错误数据", brandId: 999999, categoryId: 999999)]
        do { try await manager.restore(invalid); XCTFail("Restore must reject broken associations") } catch { }
        let after = try await manager.snapshot()
        XCTAssertEqual(after.brands.count, original.brands.count)
        XCTAssertEqual(after.brands.first?.name, original.brands.first?.name)
        XCTAssertTrue(after.items.isEmpty)
    }

    func testExportRestoreIncludesImagesAndRelationships() async throws {
        let source = try LolitaDatabase(path: ":memory:")
        let image = try XCTUnwrap(ImageFileHelper.save(imageData: Data([1, 2, 3, 4])))
        defer { ImageFileHelper.delete(path: image) }
        try await source.dbQueue.write { db in
            var brand = Brand(name: "测试品牌"); try brand.insert(db)
            var category = Category(name: "JSK"); try category.insert(db)
            var item = Item(name: "裙子", brandId: brand.id, categoryId: category.id, colors: StringList(["白色"]), imageUrls: StringList([image]))
            try item.insert(db)
            var log = OutfitLog(date: 1000, note: "测试穿搭"); try log.insert(db)
            try OutfitItemCrossRef(outfitLogId: log.id, itemId: item.id).insert(db)
        }
        let manager = BackupManager(db: source.dbQueue)
        let json = try await manager.exportJSON()
        let preview = try BackupManager.preview(json)
        XCTAssertEqual(preview.imageData.count, 1)
        XCTAssertEqual(preview.missingImageCount, 0)
        let target = try LolitaDatabase(path: ":memory:")
        let targetManager = BackupManager(db: target.dbQueue)
        try await targetManager.restore(preview)
        let restored = try await targetManager.snapshot()
        let restoredPath = try XCTUnwrap(restored.items.first?.imageUrls.values.first)
        defer { ImageFileHelper.delete(path: restoredPath) }
        XCTAssertNotEqual(restoredPath, image)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: restoredPath)), Data([1, 2, 3, 4]))
        XCTAssertEqual(restored.items.first?.colors.values, ["白色"])
        XCTAssertEqual(restored.outfitItemCrossRefs.first?.itemId, restored.items.first?.id)
    }

    func testInvalidBackupRejectedBeforeRestore() {
        XCTAssertThrowsError(try BackupManager.preview(Data("{}".utf8)))
        XCTAssertThrowsError(try BackupManager.preview(Data(#"{"items":[],"brands":[{"id":0,"name":"无效ID"}],"categories":[]}"#.utf8)))
    }

    @MainActor
    func testCancelLocationPhotoChangePreservesSavedImage() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        let original = try XCTUnwrap(ImageFileHelper.save(imageData: Data([1, 2, 3])))
        defer { ImageFileHelper.delete(path: original) }
        let repo = LocationRepository(db: database.dbQueue)
        let location = try await repo.insert(Location(name: "衣橱", imageUrl: original))
        let vm = LocationEditViewModel(locationId: location.id, repository: repo)
        await vm.load()
        XCTAssertFalse(vm.hasChanges)
        vm.setImage(data: Data([4, 5, 6]))
        XCTAssertTrue(vm.hasChanges)
        let replacement = try XCTUnwrap(vm.imageUrl)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original))
        vm.discardImages()
        XCTAssertTrue(FileManager.default.fileExists(atPath: original))
        XCTAssertFalse(FileManager.default.fileExists(atPath: replacement))
        let stored = try await repo.getById(location.id)
        XCTAssertEqual(stored?.imageUrl, original)
    }

    @MainActor
    func testFailedLocationSaveKeepsOriginalAndReplacementUntilCancel() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        let original = try XCTUnwrap(ImageFileHelper.save(imageData: Data([1, 2])))
        defer { ImageFileHelper.delete(path: original) }
        let repo = LocationRepository(db: database.dbQueue)
        let location = try await repo.insert(Location(name: "位置A", imageUrl: original))
        _ = try await repo.insert(Location(name: "位置B"))
        let vm = LocationEditViewModel(locationId: location.id, repository: repo)
        await vm.load()
        vm.setImage(data: Data([3, 4]))
        let replacement = try XCTUnwrap(vm.imageUrl)
        defer { ImageFileHelper.delete(path: replacement) }
        vm.name = "位置B"
        do { try await vm.save(); XCTFail("Duplicate name must fail") } catch { }
        XCTAssertTrue(FileManager.default.fileExists(atPath: original))
        XCTAssertTrue(FileManager.default.fileExists(atPath: replacement))
        let stored = try await repo.getById(location.id)
        XCTAssertEqual(stored?.name, "位置A")
        XCTAssertEqual(stored?.imageUrl, original)
        vm.discardImages()
        XCTAssertFalse(FileManager.default.fileExists(atPath: replacement))
    }

    func testDeletingOneItemDoesNotRemoveSharedImage() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        let path = try XCTUnwrap(ImageFileHelper.save(imageData: Data([1, 2])))
        defer { ImageFileHelper.delete(path: path) }
        let items = try await database.dbQueue.write { db in
            var brand = Brand(name: "品牌"); try brand.insert(db)
            var category = Category(name: "分类"); try category.insert(db)
            var first = Item(name: "A", brandId: brand.id, categoryId: category.id, imageUrls: StringList([path])); try first.insert(db)
            var second = Item(name: "B", brandId: brand.id, categoryId: category.id, imageUrls: StringList([path])); try second.insert(db)
            return [first, second]
        }
        let repo = ItemRepository(db: database.dbQueue)
        try await repo.delete(items[0])
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        try await repo.delete(items[1])
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }
}
