import XCTest
@preconcurrency import GRDB
@testable import lolita

final class ImportSessionRegressionTests: XCTestCase {
    private func fixture() async throws -> (DatabaseQueue, Int64, Int64) {
        let q = try LolitaDatabase(path: ":memory:").dbQueue
        return try await q.write { db in
            var b = Brand(name: "导入品牌"); try b.insert(db)
            var c = Category(name: "JSK", categorySemantic: .jsk); try c.insert(db)
            return (q,b.id,c.id)
        }
    }
    private func order(_ id: String = "source-1", quantity: Int = 1, paid: String = "100.00", shipping: String = "0.00", name: String = "导入样本") -> TaobaoOrder {
        let item = TaobaoOrderItem(orderId:id,lineIndex:0,orderTime:"2026-10-01 12:00",shopName:"导入品牌",name:name,productURL:"https://item.taobao.com/item.htm?id=123&spm=tracking",styleSpec:"蓝色;M;JSK",quantity:quantity,price:100,parsedType:"JSK",parsedSize:"M",parsedColor:"蓝色",rawPrice:"100")
        return TaobaoOrder(orderId:id,orderTime:item.orderTime,orderStatus:"交易成功",shopName:item.shopName,totalPaid:Double(paid) ?? 0,shipping:Double(shipping) ?? 0,items:[item],rawPaid:paid,rawShipping:shipping)
    }
    private func prepared(_ q: DatabaseQueue, _ b: Int64, _ c: Int64, order: TaobaoOrder) async throws -> (OrderImportSession, OrderImportSnapshot, [TaobaoImportDraft]) {
        var drafts = try OrderImportSource.drafts(order)
        for i in drafts.indices { drafts[i].brandId = b; drafts[i].categoryId = c; drafts[i].financialConfirmed = true }
        let snapshot = OrderImportSnapshot(orders:[order], selectedKeys:[order.items[0].id],step:.detail)
        var session = OrderImportSession(dataJson:"{}"); session.pendingOperationId = UUID().uuidString
        session = try await OrderImportSessionRepository(db:q).save(session,snapshot:snapshot,drafts:drafts,files:[])
        return (session,snapshot,drafts)
    }
    private func fails(_ action: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do { try await action(); XCTFail("应拒绝无效操作",file:file,line:line) } catch {}
    }
    private func eq<T: Equatable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) { XCTAssertEqual(a,b,file:file,line:line) }
    func testStableUnitIdentitySurvivesRowReorderAndUsesQuantity() throws {
        var o = order(quantity:2); var other = o.items[0]; other.sourceKey = nil
        other = TaobaoOrderItem(orderId:o.orderId,lineIndex:1,orderTime:o.orderTime,shopName:o.shopName,name:"小物",productURL:"https://item.taobao.com/item.htm?id=456",styleSpec:"黑色",quantity:1,price:20,parsedType:nil,parsedSize:nil,parsedColor:nil)
        o.items.append(other); let before = try OrderImportSource.units(o).map(\.id)
        o.items.reverse(); eq(try OrderImportSource.units(o).map(\.id),before); eq(before.count,3); eq(Set(before).count,3)
    }
    func testStrictMoneyMissingIsNotZeroAndIntegerAllocationPreservesCents() throws {
        for text in ["", "NaN", "-1", "1.001", "1e2", "1,2", "∞"] { XCTAssertThrowsError(try OrderImportSource.money(text)) }
        eq(try OrderImportSource.money("￥1,200.50"),120050)
        eq(OrderImportSource.allocate(101,weights:[1,1,1]),[34,34,33])
        eq(OrderImportSource.allocate(1,weights:[0,0]),[1,0])
        let drafts = try OrderImportSource.drafts(order(quantity:3,paid:"100.01",shipping:"1.00"))
        eq(try drafts.reduce(Int64(0)) { try $0 + OrderImportSource.money($1.paidText) },10001)
        eq(try drafts.reduce(Int64(0)) { try $0 + OrderImportSource.money($1.shippingText) },100)
        let missing = try OrderImportSource.drafts(order(paid:"",shipping:"")); eq(missing[0].paidText,""); eq(missing[0].shippingText,"")
    }
    func testPublicURLStripsTrackingRejectsCredentialsAndForeignHost() {
        eq(OrderImportSource.publicURL("http://item.taobao.com/item.htm?id=123&spm=private"),"https://item.taobao.com/item.htm?id=123")
        for url in ["file:///tmp/image.jpg", "https://item.taobao.com.evil.test/?id=1", "https://user:pass@item.taobao.com/?id=1", "https://item.taobao.com:443/?id=1", "https://item.taobao.com/?id=a"] { XCTAssertNil(OrderImportSource.publicURL(url)) }
    }
    func testFileConflictsRequireExplicitVersionAndDoNotSelectFirst() throws {
        let a = order(), b = order(paid:"90")
        let files = try [a,a,b].enumerated().map { OrderImportFile(sessionId:"s",name:"\($0.offset).xlsx",sha256:OrderImportSource.hash("\($0.offset)"),dataJson:try OrderImportSource.json([$0.element])) }
        let m = OrderImportSessionRepository.merge(files,choices:[:]); eq(m.orders.count,0); eq(m.conflicts.count,1); eq(m.duplicates,1)
        let chosen = OrderImportSessionRepository.merge(files,choices:[a.orderId:OrderImportSource.snapshot(b)]); eq(chosen.orders,[b]); eq(chosen.conflicts.count,0)
    }
    func testSessionRevisionRejectsStaleSaveAndRestoresRawInputAndPhotos() async throws {
        let (q,b,c) = try await fixture(); let repo = OrderImportSessionRepository(db:q)
        let (s,snapshot,rows) = try await prepared(q,b,c,order:order())
        var drafts = rows; drafts[0].priceText = "1."; drafts[0].manualBalanceText = "未完输入"
        let path = try XCTUnwrap(ImageFileHelper.save(imageData:Data([1,2,3]))); defer { ImageFileHelper.delete(path:path) }
        drafts[0].imagePath = path
        let saved = try await repo.save(s,snapshot:snapshot,drafts:drafts,files:[])
        await fails { _ = try await repo.save(s,snapshot:snapshot,drafts:rows,files:[]) }
        let loaded = try await repo.load(saved.id); eq(loaded.drafts[0].priceText,"1."); eq(loaded.drafts[0].manualBalanceText,"未完输入"); eq(loaded.drafts[0].imagePath,path)
        try ImageFileHelper.deleteUnreferenced(paths:[path],db:q); XCTAssertTrue(FileManager.default.fileExists(atPath:path))
        try await repo.discard(saved.id); XCTAssertFalse(FileManager.default.fileExists(atPath:path))
    }
    func testCommitIsAtomicIdempotentAndKeepsUnknownPaidDate() async throws {
        let (q,b,c) = try await fixture(); let repo = OrderImportSessionRepository(db:q)
        let (s,snapshot,rows) = try await prepared(q,b,c,order:order())
        let first = try await repo.commit(session:s,snapshot:snapshot,drafts:rows)
        let retry = try await repo.commit(session:s,snapshot:snapshot,drafts:rows); eq(first,retry); eq(first.itemIds.count,1)
        try await q.read { db in
            XCTAssertEqual(try Item.fetchCount(db),1); XCTAssertEqual(try Price.fetchCount(db),1); XCTAssertEqual(try PaymentStage.fetchCount(db),1)
            let payment = try XCTUnwrap(Payment.fetchOne(db)); XCTAssertNil(payment.paidDate); XCTAssertEqual(payment.dueDate,0)
            XCTAssertEqual(try OrderImportCommit.fetchCount(db),1); XCTAssertEqual(try OrderImportReceipt.fetchCount(db),1)
            XCTAssertEqual(try ItemSourceRecord.fetchOne(db)?.publicUrl,"https://item.taobao.com/item.htm?id=123")
        }
    }
    func testUnconfirmedFinancialRowAndInvalidPairRollBackAllBusinessTables() async throws {
        let (q,b,c) = try await fixture(); let repo = OrderImportSessionRepository(db:q)
        let (s,snapshot,rows) = try await prepared(q,b,c,order:order(quantity:2))
        var invalid = rows; invalid[1].financialConfirmed = false
        let saved = try await repo.save(s,snapshot:snapshot,drafts:invalid,files:[])
        await fails { _ = try await repo.commit(session:saved,snapshot:snapshot,drafts:invalid) }
        eq(try await q.read { try Item.fetchCount($0) },0); eq(try await q.read { try OrderImportCommit.fetchCount($0) },0)
        invalid[1].financialConfirmed = true; invalid[0].pairedWith = "missing"
        let next = try await repo.save(saved,snapshot:snapshot,drafts:invalid,files:[])
        await fails { _ = try await repo.commit(session:next,snapshot:snapshot,drafts:invalid) }
        eq(try await q.read { try Item.fetchCount($0) },0)
    }
    func testPartialSelectionKeepsSkippedAllocationAndOrderCapsAcrossSessions() async throws {
        let (q,b,c) = try await fixture(); let repo = OrderImportSessionRepository(db:q)
        let o = order(quantity:2,paid:"100",shipping:"2")
        let (s,snapshot,all) = try await prepared(q,b,c,order:o); var rows = all; rows[1].included = false
        let saved = try await repo.save(s,snapshot:snapshot,drafts:rows,files:[])
        _ = try await repo.commit(session:saved,snapshot:snapshot,drafts:rows)
        eq(try await q.read { try Payment.fetchOne($0)?.amount },50)
        let (second,next,all2) = try await prepared(q,b,c,order:o); var remaining = all2; remaining[0].included = false; remaining[1].paidText = "100"; remaining[1].priceText = "100"
        let latest = try await repo.save(second,snapshot:next,drafts:remaining,files:[])
        await fails { _ = try await repo.commit(session:latest,snapshot:next,drafts:remaining) }
        eq(try await q.read { try Item.fetchCount($0) },1)
    }
    func testDeletedReceiptRequiresExplicitReimportAndKeepsTombstone() async throws {
        let (q,b,c) = try await fixture(); let repo = OrderImportSessionRepository(db:q)
        let (s,snapshot,rows) = try await prepared(q,b,c,order:order()); _ = try await repo.commit(session:s,snapshot:snapshot,drafts:rows)
        try await q.write { db in try db.execute(sql:"DELETE FROM orderBindings"); try Item.deleteAll(db) }
        let (s2,v2,r2) = try await prepared(q,b,c,order:order())
        await fails { _ = try await repo.commit(session:s2,snapshot:v2,drafts:r2) }
        var allowed = r2; allowed[0].allowDeletedReimport = true
        let latest = try await repo.save(s2,snapshot:v2,drafts:allowed,files:[]); _ = try await repo.commit(session:latest,snapshot:v2,drafts:allowed)
        eq(try await q.read { try OrderImportReceipt.fetchCount($0) },2)
        eq(try await q.read { try OrderImportReceipt.filter(sql:"itemId IS NULL").fetchCount($0) },1)
    }
    func testLegacyIdentityMustLinkExistingWithoutDuplicatingMoney() async throws {
        let (q,b,c) = try await fixture(); let o = order(); let repo = OrderImportSessionRepository(db:q)
        let old = try await q.write { db in var i = Item(name:"原物品",brandId:b,categoryId:c,importOrderKeys:StringList([o.items[0].id]),createdAt:11,updatedAt:22); try i.insert(db); return i }
        let (s,snapshot,rows) = try await prepared(q,b,c,order:o)
        await fails { _ = try await repo.commit(session:s,snapshot:snapshot,drafts:rows) }
        var linked = rows; linked[0].linkedItemId = old.id; linked[0].identityConfirmed = true
        let latest = try await repo.save(s,snapshot:snapshot,drafts:linked,files:[]); let result = try await repo.commit(session:latest,snapshot:snapshot,drafts:linked)
        eq(result.linkedCount,1); eq(result.importedCount,0)
        eq(try await q.read { try OrderImportSource.json(Item.fetchOne($0,key:old.id)) },try OrderImportSource.json(old))
        eq(try await q.read { try Payment.fetchCount($0) },0)
    }
    func testSourceVersionChangeNeedsAcknowledgmentAndNeverOverwritesExisting() async throws {
        let (q,b,c) = try await fixture(); let repo = OrderImportSessionRepository(db:q)
        let (s,v,r) = try await prepared(q,b,c,order:order()); _ = try await repo.commit(session:s,snapshot:v,drafts:r)
        let (s2,v2,r2) = try await prepared(q,b,c,order:order(paid:"90"))
        await fails { _ = try await repo.commit(session:s2,snapshot:v2,drafts:r2) }
        var acknowledged = r2; acknowledged[0].identityConfirmed = true
        let latest = try await repo.save(s2,snapshot:v2,drafts:acknowledged,files:[]); let result = try await repo.commit(session:latest,snapshot:v2,drafts:acknowledged)
        eq(result.duplicateCount,1); eq(try await q.read { try Payment.fetchOne($0)?.amount },100)
    }
    func testSnapshotChangesCannotReuseACommittedOperation() async throws {
        let (q,b,c) = try await fixture(); let repo = OrderImportSessionRepository(db:q)
        let (s,v,r) = try await prepared(q,b,c,order:order()); _ = try await repo.commit(session:s,snapshot:v,drafts:r)
        var changed = r; changed[0].name = "不同提交"
        await fails { _ = try await repo.commit(session:s,snapshot:v,drafts:changed) }
    }
    func testDiscardAfterCommitPreservesItemImagesAndReceipt() async throws {
        let (q,b,c) = try await fixture(); let repo = OrderImportSessionRepository(db:q)
        let (s,v,r) = try await prepared(q,b,c,order:order()); var rows = r
        let path = try XCTUnwrap(ImageFileHelper.save(imageData:Data([4,5,6]))); defer { ImageFileHelper.delete(path:path) }; rows[0].imagePath = path
        let latest = try await repo.save(s,snapshot:v,drafts:rows,files:[]); _ = try await repo.commit(session:latest,snapshot:v,drafts:rows)
        try await repo.discard(s.id)
        eq(try await q.read { try Item.fetchCount($0) },1); eq(try await q.read { try OrderImportReceipt.fetchCount($0) },1)
        XCTAssertTrue(FileManager.default.fileExists(atPath:path)); eq(try await q.read { try OrderImportCommit.fetchOne($0)?.sessionId },nil)
    }
    func testV7MigrationPreservesEveryOldColumnAndActualPictureBytes() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path; defer { try? FileManager.default.removeItem(atPath:path) }
        let q = try LolitaDatabase(path:path,migrationTarget:"v7-wardrobe-storage").dbQueue
        let picture = try XCTUnwrap(ImageFileHelper.save(imageData:Data([1,7,8]))); defer { ImageFileHelper.delete(path:picture) }
        let before = try q.write { db -> [String:[Row]] in
            try PresetData.seed(db)
            try db.execute(sql:"INSERT INTO items(id,name,brandId,categoryId,imageUrls,createdAt,updatedAt) SELECT 99,'旧原图',(SELECT id FROM brands LIMIT 1),(SELECT id FROM categories LIMIT 1),?,111,222",arguments:[StringList([picture])])
            try ItemDraft.make(id:"old-draft",item:Item.fetchOne(db,key:99)!,baseline:222).insert(db)
            let names = try String.fetchAll(db,sql:"SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name!='grdb_migrations'")
            return try Dictionary(uniqueKeysWithValues:names.map { ($0,try Row.fetchAll(db,sql:"SELECT * FROM \($0) ORDER BY rowid")) })
        }
        try q.close()
        let upgraded = try LolitaDatabase(path:path).dbQueue
        try upgraded.read { db in for (table,rows) in before { XCTAssertEqual(try Row.fetchAll(db,sql:"SELECT * FROM \(table) ORDER BY rowid"),rows,table) }; XCTAssertEqual(try String.fetchOne(db,sql:"PRAGMA integrity_check"),"ok"); XCTAssertEqual(try Row.fetchAll(db,sql:"PRAGMA foreign_key_check").count,0) }
        eq(try Data(contentsOf:URL(fileURLWithPath:picture)),Data([1,7,8])); eq(before.count,20)
    }
    func testUnpersistedRowMutationCannotCommitWithAnOldSessionRevision() async throws {
        let (q,b,c) = try await fixture(); let repo = OrderImportSessionRepository(db:q)
        let (session,snapshot,rows) = try await prepared(q,b,c,order:order())
        var changed = rows; changed[0].name = "未保存修改"
        await fails { _ = try await repo.commit(session:session,snapshot:snapshot,drafts:changed) }
        eq(try await q.read { try Item.fetchCount($0) },0)
    }
    func testNumericFormattingDoesNotInventSourceConflictsAndZeroPaymentIsNotFabricated() async throws {
        let (q,b,c) = try await fixture(); let repo = OrderImportSessionRepository(db:q)
        let first = order(paid:"100.00",shipping:"0.00"), formatted = order(paid:"100",shipping:"0")
        eq(OrderImportSource.snapshot(first),OrderImportSource.snapshot(formatted))
        let (session,snapshot,rows) = try await prepared(q,b,c,order:order(paid:"0"))
        let result = try await repo.commit(session:session,snapshot:snapshot,drafts:rows)
        eq(result.importedCount,1); eq(try await q.read { try Payment.fetchCount($0) },0)
    }

    func testLinkedSourceReservesItsReviewedShareWithoutAddingPayments() async throws {
        let (q,b,c) = try await fixture(); let repo = OrderImportSessionRepository(db:q)
        let item = try await q.write { db in var i = Item(name:"关联原物品",brandId:b,categoryId:c); try i.insert(db); return i }
        let o = order(quantity:2)
        let (s,v,r) = try await prepared(q,b,c,order:o); var linked = r
        linked[0].linkedItemId = item.id; linked[0].identityConfirmed = true; linked[1].included = false
        let saved = try await repo.save(s,snapshot:v,drafts:linked,files:[]); _ = try await repo.commit(session:saved,snapshot:v,drafts:linked)
        eq(try await q.read { try Payment.fetchCount($0) },0)
        eq(try await q.read { try OrderImportReceipt.fetchOne($0)?.paidCents },5000)
        let (s2,v2,r2) = try await prepared(q,b,c,order:o); var remaining = r2
        remaining[0].included = false; remaining[1].paidText = "100"; remaining[1].priceText = "100"
        let next = try await repo.save(s2,snapshot:v2,drafts:remaining,files:[])
        await fails { _ = try await repo.commit(session:next,snapshot:v2,drafts:remaining) }
        eq(try await q.read { try Item.fetchCount($0) },1)
    }

    func testOrderFilesReceiptsAndDeletedTombstonesRoundTripWithImagesAndFullLedger() async throws {
        let (q,b,c) = try await fixture(); let repo = OrderImportSessionRepository(db:q), source = order()
        let (s,v,r) = try await prepared(q,b,c,order:source); var rows = r
        let bytes = Data([7,8,9]), picture = try XCTUnwrap(ImageFileHelper.save(imageData:Data([7,8,9]))); defer { ImageFileHelper.delete(path:picture) }
        rows[0].imagePath = picture
        let file = OrderImportFile(sessionId:s.id,name:"来源.xlsx",sha256:OrderImportSource.fileHash(bytes),dataJson:try OrderImportSource.json([source]))
        let saved = try await repo.save(s,snapshot:v,drafts:rows,files:[file]); _ = try await repo.commit(session:saved,snapshot:v,drafts:rows)
        let manager = BackupManager(db:q), original = try await manager.snapshot()
        let target = try LolitaDatabase(path:":memory:").dbQueue, restore = BackupManager(db:target)
        let json = try await manager.exportJSON(); try await restore.restore(BackupManager.preview(json))
        let zip = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".zip"); defer { try? FileManager.default.removeItem(at:zip) }
        try await manager.exportZIP().write(to:zip); try await restore.restore(BackupManager.prepare(at:zip))
        let copied = try await restore.snapshot(); defer { ImageFileHelper.delete(paths:Array(copied.imagePaths)) }
        eq(copied.orderImportFiles[0].dataJson,original.orderImportFiles[0].dataJson)
        eq(copied.orderImportReceipts.count,1); eq(copied.orderImportReceipts[0].paidCents,10000)
        eq(copied.orderImportReceipts[0].commitId,copied.orderImportCommits[0].id)
        eq(copied.payments[0].amount,100); XCTAssertNil(copied.payments[0].paidDate)
        for path in copied.imagePaths { eq(try Data(contentsOf:ImageFileHelper.fileURL(for:path)),bytes) }
        try await ItemRepository(db:target).delete(copied.items[0])
        let tombstone = try await restore.snapshot(); XCTAssertNil(tombstone.orderImportReceipts[0].itemId)
        let third = try LolitaDatabase(path:":memory:").dbQueue
        let tombstoneJSON = try await restore.exportJSON(); try await BackupManager(db:third).restore(BackupManager.preview(tombstoneJSON))
        let thirdCopy = try await BackupManager(db:third).snapshot(); defer { ImageFileHelper.delete(paths:Array(thirdCopy.imagePaths)) }
        XCTAssertNil(thirdCopy.orderImportReceipts[0].itemId); eq(thirdCopy.orderImportCommits.count,1)
    }

}
