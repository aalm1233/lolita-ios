import XCTest
import GRDB
@testable import lolita

final class PriceEditorSnapshotRegressionTests: XCTestCase {
    private static func fixture(_ db: Database) throws -> Item {
        var brand = Brand(name: "品牌"); try brand.insert(db)
        var category = Category(name: "分类"); try category.insert(db)
        var item = Item(name: "服饰", brandId: brand.id, categoryId: category.id); try item.insert(db)
        return item
    }

    @MainActor
    func testSaveUsesSubmittedTypeWhileDatabaseReadIsWaiting() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        let item = try await database.dbQueue.write { @Sendable db in try Self.fixture(db) }
        let repository = PriceRepository(db: database.dbQueue)
        let price = try await repository.saveWithPayments(Price(itemId: item.id, type: .full, totalPrice: 100))
        let vm = PriceEditViewModel(itemId: item.id, priceId: price.id, repository: repository)
        await vm.load()
        vm.totalPriceText = "500"
        vm.depositText = "无效旧输入"
        vm.balanceText = ""
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let queue = database.dbQueue
        let blocker = Task.detached {
            try queue.write { _ in entered.signal(); release.wait() }
        }
        defer { release.signal() }
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async { entered.wait(); continuation.resume() }
        }
        let saving = Task { try await vm.save() }
        for _ in 0..<100 {
            if vm.isSaving { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(vm.isSaving)
        vm.type = .depositBalance
        vm.depositText = "0"
        vm.balanceText = "0"
        release.signal()
        try await saving.value
        try await blocker.value
        let stored = try await repository.getById(price.id)
        XCTAssertEqual(stored?.type, .full)
        XCTAssertEqual(stored?.totalPrice, 500)
        let payments = try await queue.read { @Sendable db in try Payment.filter(Payment.Columns.priceId == price.id).fetchAll(db) }
        XCTAssertEqual(payments.map(\.amount), [500])
    }

    @MainActor
    func testMissingEditedPriceThrowsInsteadOfDismissingAsSuccessfulSave() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        let item = try await database.dbQueue.write { @Sendable db in try Self.fixture(db) }
        let vm = PriceEditViewModel(itemId: item.id, priceId: 999, repository: PriceRepository(db: database.dbQueue))
        vm.totalPriceText = "100"
        do { try await vm.save(); XCTFail("已删除的价格不能报告成功") }
        catch { XCTAssertTrue(error.localizedDescription.contains("已被删除")) }
        XCTAssertFalse(vm.isSaving)
        XCTAssertEqual(vm.totalPriceText, "100")
    }
}
