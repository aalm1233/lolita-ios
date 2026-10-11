import XCTest
import GRDB
@testable import lolita

final class FeatureIntegrationRegressionTests: XCTestCase {
    func testCalendarBackgroundIsRetainedUntilPreferenceIsCleared() throws {
        let database = try LolitaDatabase(path: ":memory:")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = folder.appendingPathComponent("calendar.jpg")
        try Data([1, 2, 3]).write(to: image)
        let defaults = UserDefaults.standard
        let old = defaults.object(forKey: "paymentCalendarBackgroundPath")
        defer { if let old { defaults.set(old, forKey: "paymentCalendarBackgroundPath") } else { defaults.removeObject(forKey: "paymentCalendarBackgroundPath") } }
        defaults.set(image.path, forKey: "paymentCalendarBackgroundPath")
        try ImageFileHelper.deleteUnreferenced(paths: [image.path], db: database.dbQueue, imagesDirectory: folder)
        XCTAssertTrue(FileManager.default.fileExists(atPath: image.path))
        defaults.removeObject(forKey: "paymentCalendarBackgroundPath")
        try ImageFileHelper.deleteUnreferenced(paths: [image.path], db: database.dbQueue, imagesDirectory: folder)
        XCTAssertFalse(FileManager.default.fileExists(atPath: image.path))
    }

    func testBackgroundPreferenceMovesToCurrentSandboxWithoutLosingFile() throws {
        let database = try LolitaDatabase(path: ":memory:")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = folder.appendingPathComponent("calendar.jpg")
        try Data([1, 2, 3]).write(to: image)
        let defaults = UserDefaults.standard
        let old = defaults.object(forKey: "paymentCalendarBackgroundPath")
        defer { if let old { defaults.set(old, forKey: "paymentCalendarBackgroundPath") } else { defaults.removeObject(forKey: "paymentCalendarBackgroundPath") } }
        defaults.set("/old/Containers/Data/Application/\(UUID().uuidString)/Documents/images/calendar.jpg", forKey: "paymentCalendarBackgroundPath")
        try ImageFileHelper.migrateStoredPaths(db: database.dbQueue, imagesDirectory: folder)
        XCTAssertEqual(defaults.string(forKey: "paymentCalendarBackgroundPath"), image.path)
        XCTAssertEqual(try Data(contentsOf: image), Data([1, 2, 3]))
    }

    @MainActor
    func testEditingImportedItemPreservesDeduplicationKeys() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        let item = try await database.dbQueue.write { @Sendable db in
            var brand = Brand(name: "品牌"); try brand.insert(db)
            var category = Category(name: "分类"); try category.insert(db)
            var item = Item(name: "裙子", brandId: brand.id, categoryId: category.id,
                            importOrderKeys: StringList(["100:0", "200:0"]))
            try item.insert(db)
            return item
        }
        let editor = ItemEditViewModel(db: database.dbQueue)
        await editor.load(itemId: item.id)
        editor.description = "用户修改过的说明"
        try await editor.save()
        let saved = try await ItemRepository(db: database.dbQueue).getById(item.id)
        XCTAssertEqual(saved?.description, "用户修改过的说明")
        XCTAssertEqual(saved?.importOrderKeys?.values, ["100:0", "200:0"])
    }
}
