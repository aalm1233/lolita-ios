import XCTest
import GRDB
@testable import lolita

final class DailyReviewRegressionTests: XCTestCase {
    private static func fixture() async throws -> (DatabaseQueue, Item, Item, Item) {
        let q=try LolitaDatabase(path:":memory:").dbQueue
        return try await q.write { db in
            var b=Brand(name:"品牌");try b.insert(db);var c=Category(name:"JSK");try c.insert(db)
            var parent=Item(name:"主件",brandId:b.id,categoryId:c.id);try parent.insert(db)
            var child=Item(name:"共价小物",brandId:b.id,categoryId:c.id,parentItemId:parent.id,includedInParentPrice:true);try child.insert(db)
            var wish=Item(name:"心愿",brandId:b.id,categoryId:c.id,status:.wished);try wish.insert(db)
            return(q,parent,child,wish)
        }
    }
    func testReviewIncludesMissingCurrentAndSharedParentButExcludesOrdinaryWish() async throws {
        let(q,parent,child,_)=try await Self.fixture()
        let rows=try await PurchaseReviewRepository(db:q).getAll()
        XCTAssertEqual(Set(rows.map(\.id)),[parent.id,child.id]);XCTAssertTrue(rows.allSatisfy { $0.orderItemId == parent.id })
        XCTAssertTrue(rows.allSatisfy { $0.reason.contains("当前订单未设置") })
    }
    func testReviewOnlyUsesCurrentOrderAndUnknownActualDatesWithoutRewritingAnything() async throws {
        let(q,parent,child,_)=try await Self.fixture()
        let price=try await q.write { db in
            var current=Price(itemId:parent.id,type:.full,totalPrice:100,purchaseRecordStatus:.tracked);try current.insert(db)
            try OrderBinding(itemId:parent.id,priceId:current.id,purchaseRecordStatus:.tracked).insert(db)
            var old=Price(itemId:parent.id,type:.full,totalPrice:30);try old.insert(db)
            var payment=Payment(priceId:old.id,amount:30,dueDate:1,isPaid:true);try payment.insert(db)
            return current
        }
        let empty=try await PurchaseReviewRepository(db:q).getAll();XCTAssertTrue(empty.isEmpty,"历史订单日期不混入当前订单核对")
        try await q.write { db in var payment=Payment(priceId:price.id,amount:100,dueDate:1,isPaid:true);try payment.insert(db) }
        let rows=try await PurchaseReviewRepository(db:q).getAll()
        XCTAssertEqual(Set(rows.map(\.id)),[parent.id,child.id]);XCTAssertTrue(rows.allSatisfy { $0.reason == "实付日期待补" })
        try await q.write { db in try db.execute(sql:"UPDATE payments SET paidDate=2 WHERE priceId=?",arguments:[price.id]) }
        let final=try await PurchaseReviewRepository(db:q).getAll();XCTAssertTrue(final.isEmpty)
        let payments=try await q.read { db in try Payment.order(Payment.Columns.id).fetchAll(db) };XCTAssertEqual(payments.count,2);XCTAssertNil(payments[0].paidDate)
    }
    func testHistoricalOwnedRecordShowsVerificationReasonWithoutChangingOwnership() async throws {
        let(q,parent,child,_)=try await Self.fixture()
        try await q.write { db in var p=Price(itemId:parent.id,type:.full,totalPrice:100,purchaseRecordStatus:.historicalOwned);try p.insert(db);try OrderBinding(itemId:parent.id,priceId:p.id,purchaseRecordStatus:.historicalOwned).insert(db) }
        let rows=try await PurchaseReviewRepository(db:q).getAll();XCTAssertEqual(rows.count,2)
        XCTAssertTrue(rows.allSatisfy { $0.reason == "已确认拥有，付款资料待核对" && $0.item.status == .owned })
        XCTAssertEqual(rows.first(where:{$0.id == child.id})?.orderItemId,parent.id)
    }
    @MainActor
    func testQuickSaveRejectsOwnershipChangeWithinTransactionAndRetainsInputPhotos() async throws {
        let(q,parent,_,_)=try await Self.fixture();let vm=QuickOutfitLogViewModel(db:q)
        try await vm.load();vm.note="尚未保存";vm.selectedItemIds=[parent.id]
        let photo=try XCTUnwrap(ImageFileHelper.save(imageData:Data([1,2,3])));defer { ImageFileHelper.delete(path:photo) };vm.imageUrls=[photo]
        try await q.write { db in try db.execute(sql:"UPDATE items SET status='WISHED' WHERE id=?",arguments:[parent.id]) }
        do { try await vm.save();XCTFail() } catch { XCTAssertTrue(error is ValidationError) }
        XCTAssertEqual(vm.note,"尚未保存");XCTAssertEqual(vm.imageUrls,[photo]);XCTAssertTrue(FileManager.default.fileExists(atPath:photo))
        let count=try await q.read { db in try OutfitLog.fetchCount(db) };XCTAssertEqual(count,0)
    }
    func testHistoricalUnownedLinkCanBeRetainedOrRemovedButNotNewlyAdded() async throws {
        let(q,parent,_,wish)=try await Self.fixture();let repo=OutfitLogRepository(db:q)
        let old=try await repo.save(OutfitLog(date:1,note:"旧记录",imageUrls:["old.jpg"]),itemIds:[parent.id])
        try await q.write { db in try db.execute(sql:"UPDATE items SET status='WISHED' WHERE id=?",arguments:[parent.id]) }
        _=try await repo.save(old,itemIds:[parent.id])
        do { _=try await repo.save(old,itemIds:[parent.id,wish.id]);XCTFail() } catch { XCTAssertTrue(error is ValidationError) }
        let retained=try await repo.getItemIds(for:old.id);XCTAssertEqual(retained,[parent.id])
        _=try await repo.save(old,itemIds:[]);let removed=try await repo.getItemIds(for:old.id);XCTAssertTrue(removed.isEmpty)
    }
    func testAssociationWriteFailureRollsBackLogPhotosAndLinks() async throws {
        let (q, parent, child, _) = try await Self.fixture(), repo = OutfitLogRepository(db: q)
        let old = try await repo.save(OutfitLog(date: 1, note: "原笔记", imageUrls: ["original.jpg"]), itemIds: [parent.id])
        try await q.write { db in
            try db.execute(sql: "CREATE TRIGGER reject_test_link BEFORE INSERT ON outfitItemCrossRef WHEN NEW.itemId=\(child.id) BEGIN SELECT RAISE(ABORT, 'reject association'); END")
        }
        var changed = old; changed.note = "不能部分提交"; changed.imageUrls = ["new.jpg"]
        do { _ = try await repo.save(changed, itemIds: [parent.id, child.id]); XCTFail() }
        catch { XCTAssertEqual((error as? DatabaseError)?.extendedResultCode, .SQLITE_CONSTRAINT_TRIGGER) }
        let stored = try await repo.getById(old.id), links = try await repo.getItemIds(for: old.id)
        XCTAssertEqual(stored?.note, "原笔记"); XCTAssertEqual(stored?.imageUrls.values, ["original.jpg"]); XCTAssertEqual(links, [parent.id])
    }

    @MainActor
    func testOutgoingStageBindingsRemainSafeAfterAsyncEmptyPlanLoadAndRemoval() async throws {
        let (q, parent, _, _) = try await Self.fixture()
        let price = try await q.write { db in
            var value = Price(itemId: parent.id, type: .full, totalPrice: 100, purchaseRecordStatus: .tracked)
            try value.insert(db); try OrderBinding(itemId: parent.id, priceId: value.id, purchaseRecordStatus: .tracked).insert(db)
            return value
        }
        let vm = PriceEditViewModel(itemId: parent.id, priceId: price.id, repository: PriceRepository(db: q))
        let outgoing = vm.stages[0], oldBinding = vm.stageBinding(vm.stages[0])
        await vm.load()
        XCTAssertTrue(vm.isLoaded); XCTAssertTrue(vm.stages.isEmpty)
        XCTAssertEqual(oldBinding.wrappedValue.id, outgoing.id)
        var late = oldBinding.wrappedValue; late.hasDueDate = true; oldBinding.wrappedValue = late
        XCTAssertTrue(vm.stages.isEmpty, "离场控件的迟到写入不能重建阶段")
        vm.changeType(.depositBalance)
        let first = vm.stages[0], last = vm.stages[1], removedBinding = vm.stageBinding(vm.stages[1])
        vm.changeType(.full)
        XCTAssertEqual(removedBinding.wrappedValue.id, last.id)
        removedBinding.wrappedValue = last
        XCTAssertEqual(vm.stages.map(\.id), [first.id])
    }

}
