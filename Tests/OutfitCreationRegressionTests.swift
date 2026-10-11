import XCTest
import GRDB
@testable import lolita

final class OutfitCreationRegressionTests: XCTestCase {
    @MainActor
    func testCreatePastOutfitAndSaveAgainUpdatesSameRecord() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        let item = try await database.dbQueue.write { @Sendable db in
            var brand = Brand(name: "品牌"); try brand.insert(db)
            var category = Category(name: "分类"); try category.insert(db)
            var item = Item(name: "连衣裙", brandId: brand.id, categoryId: category.id); try item.insert(db)
            return item
        }
        let vm = OutfitLogEditViewModel(db: database.dbQueue)
        await vm.load(logId: 0)
        XCTAssertEqual(vm.allItems.map(\.id), [item.id])
        XCTAssertFalse(vm.hasChanges)
        vm.date = Date(timeIntervalSince1970: 1_700_000_000)
        vm.note = "补记出游"
        vm.selectedItemIds = [item.id]
        try await vm.save()
        vm.note = "补充备注"
        try await vm.save()
        let values = try await database.dbQueue.read { @Sendable db in
            (try OutfitLog.fetchAll(db), try OutfitItemCrossRef.fetchAll(db))
        }
        XCTAssertEqual(values.0.count, 1)
        XCTAssertEqual(values.0.first?.date, 1_700_000_000_000)
        XCTAssertEqual(values.0.first?.note, "补充备注")
        XCTAssertEqual(values.1.map(\.itemId), [item.id])
    }

    @MainActor
    func testNewOutfitRejectsEmptyItemsAndKeepsInput() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        let vm = OutfitLogEditViewModel(db: database.dbQueue)
        await vm.load(logId: 0)
        vm.note = "还未选衣服"
        do { try await vm.save(); XCTFail("空服饰不应保存") }
        catch { XCTAssertEqual(error.localizedDescription, "请至少选择一件穿搭服饰") }
        XCTAssertEqual(vm.note, "还未选衣服")
        XCTAssertTrue(vm.hasChanges)
        let count = try await database.dbQueue.read { @Sendable db in try OutfitLog.fetchCount(db) }
        XCTAssertEqual(count, 0)
    }

    @MainActor
    func testNewOutfitRejectsWishlistAndPendingItems() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        let items = try await database.dbQueue.write { @Sendable db in
            var brand = Brand(name: "品牌"); try brand.insert(db)
            var category = Category(name: "分类"); try category.insert(db)
            var wished = Item(name: "心愿", brandId: brand.id, categoryId: category.id, status: .wished); try wished.insert(db)
            var pending = Item(name: "尾款", brandId: brand.id, categoryId: category.id, status: .pendingBalance); try pending.insert(db)
            return [wished, pending]
        }
        let vm = OutfitLogEditViewModel(db: database.dbQueue)
        await vm.load(logId: 0)
        for item in items {
            vm.toggleItem(item.id)
            XCTAssertTrue(vm.selectedItemIds.isEmpty)
            vm.selectedItemIds = [item.id]
            do { try await vm.save(); XCTFail("未拥有服饰不能添加穿搭") }
            catch { XCTAssertTrue(error.localizedDescription.contains("已拥有")) }
            vm.selectedItemIds = []
        }
        let count = try await database.dbQueue.read { @Sendable db in try OutfitLog.fetchCount(db) }
        XCTAssertEqual(count, 0)
    }
}
