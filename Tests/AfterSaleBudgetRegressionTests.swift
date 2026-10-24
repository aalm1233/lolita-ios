import XCTest
@preconcurrency import GRDB
@testable import lolita

final class AfterSaleBudgetRegressionTests: XCTestCase {
    private static func setup() async throws -> (DatabaseQueue, Item, OrderRepository, AfterSaleRepository, FinanceRepository) {
        let q = try LolitaDatabase(path: ":memory:").dbQueue
        let item = try await q.write { @Sendable db in
            var b = Brand(name: "测试品牌"); try b.insert(db)
            var c = Category(name: "测试分类"); try c.insert(db)
            var item = Item(name: "售后样本", brandId: b.id, categoryId: c.id, status: .wished, createdAt: 111, updatedAt: 222)
            try item.insert(db); return item
        }
        return (q, item, OrderRepository(db: q), AfterSaleRepository(db: q), FinanceRepository(db: q))
    }
    private static func purchase(_ item: Item, _ repo: OrderRepository, paid: Double = 200) async throws -> OrderSnapshot {
        let price = try await repo.create(price: Price(itemId: item.id, type: .full, totalPrice: 300), stages: [PaymentStage(name: "全款", amount: 300, dueDate: 1893456000000, reminderSet: true)])
        if paid > 0 { _ = try await repo.recordPayment(priceId: price.id, amount: paid, paidDate: 1767225600000) }
        return try await repo.get(price.id)
    }
    private func expectEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) { XCTAssertEqual(actual, expected, file: file, line: line) }
    private func expectTrue(_ actual: Bool, file: StaticString = #filePath, line: UInt = #line) { XCTAssertTrue(actual, file: file, line: line) }
    private func unwrap<T>(_ actual: T?, file: StaticString = #filePath, line: UInt = #line) throws -> T { try XCTUnwrap(actual, file: file, line: line) }
    private func fails(_ action: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do { try await action(); XCTFail("此操作必须拒绝", file: file, line: line) } catch {}
    }
    func testV5MigrationAddsOnlyEmptyTablesAndPreservesAllFourteenTables() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let old = try LolitaDatabase(path: path, migrationTarget: "v5-order-ledger")
        let tables = ["brands","categories","styles","seasons","sources","locations","coordinates","items","prices","payments","outfitLogs","outfitItemCrossRef","orderBindings","paymentStages"]
        let before = try old.dbQueue.write { db -> [String:[Row]] in
            try PresetData.seed(db)
            let b = try Int64.fetchOne(db,sql:"SELECT id FROM brands LIMIT 1")!, c = try Int64.fetchOne(db,sql:"SELECT id FROM categories LIMIT 1")!
            try db.execute(sql:"INSERT INTO locations(id,name,description,sortOrder,createdAt,updatedAt,imageUrl) VALUES(77,'衣柜','旧描述',3,111,222,'old.png')")
            try db.execute(sql:"INSERT INTO coordinates(id,name,description,imageUrls,createdAt,updatedAt) VALUES(77,'旧套装','原关联','[\"old.png\"]',111,222)")
            try db.execute(sql:"INSERT INTO items(id,name,brandId,categoryId,status,description,imageUrls,colors,season,importOrderKeys,createdAt,updatedAt,locationId,coordinateId) VALUES(77,'主件',?,?,'PENDING_PAYMENT','旧描述','[\"old.png\"]','[\"白\"]','春,秋','[\"tb-77\"]',111,222,77,77)",arguments:[b,c])
            try db.execute(sql:"INSERT INTO items(id,name,brandId,categoryId,status,createdAt,updatedAt,parentItemId,includedInParentPrice) VALUES(78,'共价',?,?,'PENDING_PAYMENT',111,222,77,1)",arguments:[b,c])
            try db.execute(sql:"INSERT INTO prices(id,itemId,type,totalPrice,createdAt,shipping,purchaseRecordStatus) VALUES(77,77,'FULL',300,333,20,'TRACKED')")
            try db.execute(sql:"INSERT INTO orderBindings(itemId,priceId,purchaseRecordStatus) VALUES(77,77,'TRACKED')")
            try db.execute(sql:"INSERT INTO paymentStages(id,priceId,name,amount,dueDate,reminderSet) VALUES(77,77,'原阶段',300,NULL,0)")
            try db.execute(sql:"INSERT INTO payments(id,priceId,amount,dueDate,isPaid,paidDate,reminderSet,createdAt,operationId) VALUES(77,77,100,999,1,NULL,0,444,'original-op')")
            try db.execute(sql:"INSERT INTO outfitLogs(id,date,note,imageUrls,createdAt,updatedAt) VALUES(77,999,'旧日志','[\"old.png\"]',111,222)")
            try db.execute(sql:"INSERT INTO outfitItemCrossRef(outfitLogId,itemId) VALUES(77,77)")
            return try Dictionary(uniqueKeysWithValues: tables.map { ($0,try Row.fetchAll(db,sql:"SELECT * FROM \($0) ORDER BY rowid")) })
        }
        try old.dbQueue.close()
        for _ in 0..<2 {
            let upgraded = try LolitaDatabase(path:path)
            try upgraded.dbQueue.read { db in
                for table in tables {
                    let columns = before[table]!.first?.columnNames.map { "\"\($0)\"" }.joined(separator: ",") ?? "*"
                    XCTAssertEqual(try Row.fetchAll(db,sql:"SELECT \(columns) FROM \(table) ORDER BY rowid"),before[table],table)
                }
                for table in ["itemReferencePrices","orderRefunds","orderCancellations","monthlyBudgets"] {
                    XCTAssertEqual(try Int.fetchOne(db,sql:"SELECT COUNT(*) FROM \(table)"),0)
                }
                XCTAssertTrue(try Row.fetchAll(db,sql:"PRAGMA foreign_key_check").isEmpty)
            }
            try upgraded.dbQueue.close()
        }
    }
    func testReferenceIsIndependentZeroIsVisibleCASAndSharedChildRejected() async throws {
        let (q,item,orders,after,_) = try await Self.setup()
        try await after.saveReference(itemId:item.id,amount:0,note:"来源",expected:nil)
        let reference = try unwrap(try await after.reference(itemId:item.id))
        XCTAssertEqual(reference.amount,0)
        let state = try await q.read { @Sendable db in (try Item.fetchOne(db,key:item.id)?.status,try Price.fetchCount(db),try Payment.fetchCount(db),try OrderBinding.fetchCount(db)) }
        XCTAssertEqual(state.0,.wished); XCTAssertEqual(state.1,0); XCTAssertEqual(state.2,0); XCTAssertEqual(state.3,0)
        await fails { try await after.saveReference(itemId:item.id,amount:10,note:"",expected:nil) }
        try await after.saveReference(itemId:item.id,amount:680.12,note:"淘宝",expected:reference)
        let snapshot = try await Self.purchase(item,orders)
        let values = OrderAccounting.displayAmounts(prices:[snapshot.price],bindings:[snapshot.binding!],stages:snapshot.stages,references:[reference])
        XCTAssertEqual(values[item.id],300,"当前订单优先参考价")
        let child = try await ItemRepository(db:q).insert(Item(name:"共价",brandId:item.brandId,categoryId:item.categoryId,parentItemId:item.id,includedInParentPrice:true))
        await fails { try await after.saveReference(itemId:child.id,amount:10,note:"",expected:nil) }
    }
    func testRefundKeepsActualPlanAndStatusAndDuplicateOperationIsIdempotent() async throws {
        let (q,item,orders,after,_) = try await Self.setup(); let order = try await Self.purchase(item,orders)
        let value = OrderRefund(priceId:order.id,amount:75.25,kind:.priceDifference,receivedAt:1769904000000,note:"  差价  ",operationId:"refund-once")
        let saved = try await after.recordRefund(value,expected:order.fingerprint)
        let retry = try await after.recordRefund(value,expected:order.fingerprint)
        XCTAssertEqual(saved.id,retry.id)
        let result = try await orders.get(order.id)
        XCTAssertEqual(result.paidAmount,200); XCTAssertEqual(result.refundedAmount,75.25); XCTAssertEqual(result.netAmount,124.75)
        XCTAssertEqual(result.remainingAmount,100); XCTAssertEqual(result.payments.map(\.id),order.payments.map(\.id)); XCTAssertEqual(result.stages,order.stages)
        expectEqual(try await q.read { try Item.fetchOne($0,key:item.id)?.status },.pendingPayment)
        await fails { _ = try await after.recordRefund(OrderRefund(priceId:order.id,amount:1,receivedAt:1769904000000,operationId:"stale"),expected:order.fingerprint) }
        await fails { _ = try await after.recordRefund(OrderRefund(priceId:order.id,amount:201,receivedAt:1769904000000,operationId:"limit"),expected:result.fingerprint) }
    }
    func testRefundConcurrencyCannotExceedCashAndVoidPreservesEvidence() async throws {
        let (_,item,orders,after,_) = try await Self.setup(); let order = try await Self.purchase(item,orders)
        let successes = await withTaskGroup(of:Bool.self) { group in
            for index in 0..<8 { group.addTask {
                do { _ = try await after.recordRefund(OrderRefund(priceId:order.id,amount:150,receivedAt:1769904000000,operationId:"race-\(index)"),expected:order.fingerprint); return true } catch { return false }
            } }
            var count=0; for await success in group { if success { count += 1 } }; return count
        }
        XCTAssertEqual(successes,1)
        let fresh = try await orders.get(order.id)
        try await after.voidRefund(fresh.refunds[0].id,expected:fresh.fingerprint)
        let voided = try await orders.get(order.id)
        XCTAssertEqual(voided.refunds.count,1); XCTAssertNotNil(voided.refunds[0].voidedAt); XCTAssertEqual(voided.netAmount,200)
    }
    func testPaymentEditAndDeleteCannotUndercutRefunds() async throws {
        let (q,item,orders,after,_) = try await Self.setup(); let order = try await Self.purchase(item,orders)
        _ = try await after.recordRefund(OrderRefund(priceId:order.id,amount:150,receivedAt:1769904000000,operationId:"coverage"),expected:order.fingerprint)
        let fresh = try await orders.get(order.id); var reduced = fresh.payments[0]; reduced.amount = 149.99
        let submitted = reduced
        await fails { _ = try await PaymentRepository(db:q).saveActual(submitted,expected:fresh.fingerprint) }
        await fails { try await orders.deletePayment(fresh.payments[0].id,expected:fresh.fingerprint) }
        await fails { try await PaymentRepository(db:q).delete(fresh.payments[0]) }
        expectEqual(try await orders.get(order.id).paidAmount,200)
    }
    func testCancellationRetainsLedgerSharedLinksAndStopsPendingThenRebuyIsIndependent() async throws {
        let (q,item,orders,after,finance) = try await Self.setup(); let order = try await Self.purchase(item,orders)
        let child = try await ItemRepository(db:q).insert(Item(name:"共价小物",brandId:item.brandId,categoryId:item.categoryId,parentItemId:item.id,includedInParentPrice:true))
        let fresh = try await orders.get(order.id)
        try await after.cancelOrder(priceId:order.id,expectedRefund:nil,note:"约定待确认",expected:fresh.fingerprint,confirmed:true)
        let cancelled = try await orders.get(order.id)
        XCTAssertNil(cancelled.cancellation?.expectedRefundTotal); XCTAssertFalse(cancelled.isCurrent); XCTAssertNil(cancelled.remainingAmount)
        XCTAssertEqual(cancelled.payments.map(\.id),order.payments.map(\.id)); XCTAssertEqual(cancelled.stages,order.stages)
        let pair = try await q.read { @Sendable db in (try Item.fetchOne(db,key:item.id),try Item.fetchOne(db,key:child.id)) }
        XCTAssertEqual(pair.0?.status,.wished); XCTAssertEqual(pair.1?.status,.wished); XCTAssertEqual(pair.1?.parentItemId,item.id)
        let pending = try await finance.get().entries.filter { !$0.isPaid }; XCTAssertTrue(pending.isEmpty)
        expectTrue(try await PaymentRepository(db:q).getReminderRecords().filter { !$0.isPaid }.isEmpty)
        await fails { try await orders.bindHistorical(itemId:item.id,priceId:order.id) }
        await fails { _ = try await orders.recordPayment(priceId:order.id,amount:1,paidDate:1769904000000) }
        let rebuy = try await Self.purchase(item,orders,paid:0)
        XCTAssertNotEqual(rebuy.id,order.id); XCTAssertTrue(rebuy.payments.isEmpty)
        let still = try await orders.get(order.id); XCTAssertNotNil(still.cancellation); XCTAssertEqual(still.paidAmount,200)
    }
    func testCancellationBoundsZeroUnknownAndOldAgreementEditDoesNotCancelNewPurchase() async throws {
        let (_,item,orders,after,_) = try await Self.setup(); let order = try await Self.purchase(item,orders)
        await fails { try await after.cancelOrder(priceId:order.id,expectedRefund:nil,note:"",expected:order.fingerprint,confirmed:false) }
        await fails { try await after.cancelOrder(priceId:order.id,expectedRefund:201,note:"",expected:order.fingerprint,confirmed:true) }
        try await after.cancelOrder(priceId:order.id,expectedRefund:0,note:"不退定金",expected:order.fingerprint,confirmed:true)
        let cancelled = try await orders.get(order.id); XCTAssertEqual(cancelled.pendingRefund,0)
        let next = try await Self.purchase(item,orders,paid:0)
        let old = try await orders.get(order.id)
        try await after.cancelOrder(priceId:order.id,expectedRefund:nil,note:"改为待核对",expected:old.fingerprint,confirmed:true)
        expectTrue(try await orders.get(next.id).isCurrent)
    }
    func testCrossMonthRefundBudgetCountsArrivalAndCanBeNegative() async throws {
        let (_,item,orders,after,finance) = try await Self.setup(); let order = try await Self.purchase(item,orders)
        try await orders.archive(priceId:order.id)
        let archived = try await orders.get(order.id)
        _ = try await after.recordRefund(OrderRefund(priceId:order.id,amount:75.25,receivedAt:1769904000000,operationId:"feb"),expected:archived.fingerprint)
        try await finance.saveBudget(month:"2026-02",amount:100,expected:nil)
        var cal=Calendar(identifier:.gregorian); cal.timeZone=TimeZone(secondsFromGMT:0)!
        let all=try await finance.get(), feb=cal.date(from:DateComponents(year:2026,month:2,day:1))!
        let summary=all.month(feb,calendar:cal)
        XCTAssertEqual(summary.paid,0); XCTAssertEqual(summary.refunded,75.25); XCTAssertEqual(summary.net,-75.25); XCTAssertEqual(summary.projectedRemaining,175.25)
        XCTAssertEqual(all.totalPaid,200); XCTAssertEqual(all.totalNet,124.75)
    }
    func testBudgetPendingCarriesEarlierAndKeepsUnknownDatesSeparate() async throws {
        let (_,item,orders,_,finance) = try await Self.setup()
        _ = try await orders.create(price:Price(itemId:item.id,type:.multiStage,totalPrice:1000),stages:[PaymentStage(name:"以前",amount:200,dueDate:1767225600000),PaymentStage(name:"本月",amount:300,dueDate:1769904000000),PaymentStage(name:"未定",amount:500)])
        let price = try await finance.get().entries[0].priceId
        _ = try await orders.recordPayment(priceId:price,amount:100,paidDate:1767225600000)
        try await finance.saveBudget(month:"2026-02",amount:1000,expected:nil)
        var cal=Calendar(identifier:.gregorian); cal.timeZone=TimeZone(secondsFromGMT:0)!
        let result=try await finance.get().month(cal.date(from:DateComponents(year:2026,month:2,day:1))!,calendar:cal)
        XCTAssertEqual(result.earlierPending,100); XCTAssertEqual(result.pending,300); XCTAssertEqual(result.undatedPending,500); XCTAssertEqual(result.projectedRemaining,600)
        XCTAssertEqual(result.entries.filter { !$0.isPaid }.count,2)
    }
    func testBudgetZeroCASAndInvalidInputs() async throws {
        let (_,_,_,_,finance) = try await Self.setup()
        try await finance.saveBudget(month:"2026-02",amount:0,expected:nil)
        let current=try unwrap(try await finance.get().budgets.first)
        XCTAssertEqual(current.amountCents,0)
        await fails { try await finance.saveBudget(month:"2026-02",amount:100,expected:nil) }
        for month in ["2026-13","26-01","2026-2","2026-00"] { await fails { try await finance.saveBudget(month:month,amount:10,expected:nil) } }
        for amount in [-1.0, 1.001, .infinity] { await fails { try await finance.saveBudget(month:"2026-03",amount:amount,expected:nil) } }
        try await finance.deleteBudget(current); expectTrue(try await finance.get().budgets.isEmpty)
    }
    func testBackupJSONZIPCSVAndMalformedFinanceFailWithoutReplacingData() async throws {
        let (q,item,orders,after,finance) = try await Self.setup()
        let bytes=Data([1,9,3,5,7]), image=try XCTUnwrap(ImageFileHelper.save(imageData:Data([1,9,3,5,7])))
        defer { ImageFileHelper.delete(path:image) }
        try await q.write { @Sendable db in
            var value=try Item.fetchOne(db,key:item.id)!; value.imageUrls=StringList([image]); try value.update(db)
        }
        let order=try await Self.purchase(item,orders)
        try await after.saveReference(itemId:item.id,amount:680.12,note:"独立",expected:nil)
        _ = try await after.recordRefund(OrderRefund(priceId:order.id,amount:75.25,receivedAt:1769904000000,operationId:"backup-refund"),expected:order.fingerprint)
        let next=try await orders.get(order.id)
        try await after.cancelOrder(priceId:order.id,expectedRefund:nil,note:"未知约定",expected:next.fingerprint,confirmed:true)
        try await finance.saveBudget(month:"2026-02",amount:500,expected:nil)
        let manager=BackupManager(db:q), json=try await manager.exportJSON(), original=try await manager.snapshot()
        let preview=try BackupManager.preview(json); XCTAssertEqual(preview.iosLedgerVersion,2)
        let target=try LolitaDatabase(path:":memory:").dbQueue, restore=BackupManager(db:target)
        try await restore.restore(preview)
        let copied=try await restore.snapshot()
        XCTAssertEqual(copied.itemReferencePrices,original.itemReferencePrices); XCTAssertEqual(copied.orderRefunds,original.orderRefunds)
        XCTAssertEqual(copied.orderCancellations,original.orderCancellations); XCTAssertEqual(copied.monthlyBudgets,original.monthlyBudgets)
        let zip=try await manager.exportZIP(), url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".zip")
        defer { try? FileManager.default.removeItem(at:url) }; try zip.write(to:url)
        let prepared=try BackupManager.prepare(at:url); try await restore.restore(prepared)
        let zipped=try await restore.snapshot()
        XCTAssertEqual(zipped.orderRefunds,original.orderRefunds)
        for path in zipped.imagePaths { XCTAssertEqual(try Data(contentsOf:ImageFileHelper.fileURL(for:path)),bytes) }
        defer { for path in zipped.imagePaths { ImageFileHelper.delete(path:path) } }
        let csv=String(decoding:try await manager.exportCSV(),as:UTF8.self)
        XCTAssertEqual(csv.components(separatedBy:"=== ").count-1,20)
        var broken=preview; broken.orderRefunds[0].amount=201
        await fails { try await restore.restore(broken) }
        expectEqual(try await restore.snapshot().orderRefunds,original.orderRefunds)
        var root=try XCTUnwrap(JSONSerialization.jsonObject(with:json) as? [String:Any]); root.removeValue(forKey:"orderRefunds")
        XCTAssertThrowsError(try BackupManager.preview(JSONSerialization.data(withJSONObject:root)))
    }
    func testOldNativeLedgerVersionOneBackupStillRestores() async throws {
        let (q,item,orders,_,_) = try await Self.setup(); _ = try await Self.purchase(item,orders)
        var root=try unwrap(JSONSerialization.jsonObject(with:try await BackupManager(db:q).exportJSON()) as? [String:Any])
        root["iosLedgerVersion"]=1
        for key in ["itemReferencePrices","orderRefunds","orderCancellations","monthlyBudgets"] { root.removeValue(forKey:key) }
        let preview=try BackupManager.preview(JSONSerialization.data(withJSONObject:root))
        let target=try LolitaDatabase(path:":memory:").dbQueue
        try await BackupManager(db:target).restore(preview)
        let restored=try await BackupManager(db:target).snapshot()
        XCTAssertEqual(restored.payments.count,1); XCTAssertEqual(restored.orderBindings.count,1); XCTAssertTrue(restored.orderRefunds.isEmpty)
    }
    @MainActor
    func testReferenceAdoptionIsExplicitDraftUntilOrderSave() async throws {
        let (q,item,_,after,_) = try await Self.setup()
        try await after.saveReference(itemId:item.id,amount:680.12,note:"来源",expected:nil)
        let editor = PriceEditViewModel(itemId:item.id,repository:PriceRepository(db:q))
        await editor.load(); XCTAssertEqual(editor.totalPriceText, "")
        editor.adoptReference(); XCTAssertEqual(editor.totalPriceText,"680.12")
        let before = try await q.read { try Price.fetchCount($0) }; XCTAssertEqual(before,0)
        try await editor.save()
        let state = try await q.read { db in (try Price.fetchCount(db),try Payment.fetchCount(db),try ItemReferencePrice.fetchCount(db)) }
        XCTAssertEqual(state.0,1); XCTAssertEqual(state.1,0); XCTAssertEqual(state.2,1)
    }
    func testInvalidRefundAndVoidedOperationCannotBeReplayedAsNewCash() async throws {
        let (_,item,orders,after,_) = try await Self.setup(); let order=try await Self.purchase(item,orders)
        for amount in [0.0,-1,1.001,Double.infinity,Double.leastNonzeroMagnitude] {
            await fails { _ = try await after.recordRefund(OrderRefund(priceId:order.id,amount:amount,receivedAt:1769904000000,operationId:UUID().uuidString),expected:order.fingerprint) }
        }
        await fails { _ = try await after.recordRefund(OrderRefund(priceId:order.id,amount:1,receivedAt:Int64.max,operationId:"future"),expected:order.fingerprint) }
        let value=OrderRefund(priceId:order.id,amount:10,receivedAt:1769904000000,operationId:"void-replay")
        let saved=try await after.recordRefund(value,expected:order.fingerprint)
        let current=try await orders.get(order.id); try await after.voidRefund(saved.id,expected:current.fingerprint)
        let retried=try await after.recordRefund(value,expected:order.fingerprint)
        XCTAssertEqual(retried.id,saved.id); XCTAssertNotNil(retried.voidedAt)
        let result=try await orders.get(order.id); XCTAssertEqual(result.refundedAmount,0); XCTAssertEqual(result.refunds.count,1)
    }
    func testRefundBeyondOriginalAgreementStillBacksUpAndUnreviewedLegacyCashCannotBeRemoved() async throws {
        let (q,item,orders,after,_) = try await Self.setup(); let order=try await Self.purchase(item,orders)
        try await after.cancelOrder(priceId:order.id,expectedRefund:20,note:"原约定",expected:order.fingerprint,confirmed:true)
        let current=try await orders.get(order.id)
        _ = try await after.recordRefund(OrderRefund(priceId:order.id,amount:25,receivedAt:1769904000000,operationId:"extra-arrival"),expected:current.fingerprint)
        let backup=try await BackupManager(db:q).exportJSON(); let preview=try BackupManager.preview(backup)
        XCTAssertEqual(preview.orderCancellations[0].expectedRefundTotal,20)
        let target=try LolitaDatabase(path:":memory:").dbQueue; try await BackupManager(db:target).restore(preview)
        let restored=try await OrderRepository(db:target).get(order.id); XCTAssertEqual(restored.pendingRefund,0)
        // Direct legacy APIs cannot destroy the evidence of an associated refund.
        let legacyItem=try await ItemRepository(db:q).insert(Item(name:"旧账本",brandId:item.brandId,categoryId:item.categoryId))
        let legacy=try await PriceRepository(db:q).insert(Price(itemId:legacyItem.id,type:.full,totalPrice:100))
        let payment=try await PaymentRepository(db:q).insert(Payment(priceId:legacy.id,amount:100,dueDate:1767225600000,isPaid:true,paidDate:1767225600000))
        let old=try await orders.get(legacy.id)
        _ = try await after.recordRefund(OrderRefund(priceId:legacy.id,amount:10,receivedAt:1769904000000,operationId:"legacy-refund"),expected:old.fingerprint)
        await fails { try await PaymentRepository(db:q).delete(payment) }
        await fails { try await PaymentRepository(db:q).update(payment) }
        await fails { try await PriceRepository(db:q).delete(legacy) }
    }
    @MainActor
    func testEditorDraftRestoresOperationFingerprintInputAndRejectsStaleSave() async throws {
        let (_,item,orders,after,finance) = try await Self.setup(); let order=try await Self.purchase(item,orders)
        let suite="finance-test-"+UUID().uuidString, defaults=UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let editor=FinanceEditorViewModel(mode:.refund(order.id),afterSale:after,orders:orders,finance:finance,defaults:defaults)
        await editor.load(); XCTAssertEqual(editor.draft.amount,"")
        editor.draft.amount="75.25"; editor.draft.note="恢复输入"; editor.persist()
        let recovered=FinanceEditorViewModel(mode:.refund(order.id),afterSale:after,orders:orders,finance:finance,defaults:defaults)
        await recovered.load()
        XCTAssertEqual(recovered.draft,editor.draft); XCTAssertTrue(recovered.hasChanges)
        _ = try await orders.recordPayment(priceId:order.id,amount:10,paidDate:1769904000000)
        do { try await recovered.save(); XCTFail("陈旧草稿必须拒绝") } catch {}
        XCTAssertEqual(recovered.draft.amount,"75.25"); XCTAssertNotNil(defaults.data(forKey:recovered.draftKey))
        recovered.discard(); XCTAssertNil(defaults.data(forKey:recovered.draftKey))
        for mode in [FinanceEditorMode.reference(item.id),.cancel(order.id),.budget("2026-02")] {
            let first=FinanceEditorViewModel(mode:mode,afterSale:after,orders:orders,finance:finance,defaults:defaults)
            await first.load(); first.draft.amount="0"; first.draft.note="草稿"; first.persist()
            let second=FinanceEditorViewModel(mode:mode,afterSale:after,orders:orders,finance:finance,defaults:defaults)
            await second.load(); XCTAssertEqual(second.draft,first.draft)
        }
    }
    @MainActor
    func testRestoredReferenceRefundAndCancellationCanActuallyCommit() async throws {
        let (_,item,orders,after,finance) = try await Self.setup()
        let suite="finance-commit-"+UUID().uuidString, defaults=UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        for mode in [FinanceEditorMode.reference(item.id)] {
            let first=FinanceEditorViewModel(mode:mode,afterSale:after,orders:orders,finance:finance,defaults:defaults)
            await first.load(); first.draft.amount="680.12"; first.persist()
            let second=FinanceEditorViewModel(mode:mode,afterSale:after,orders:orders,finance:finance,defaults:defaults)
            await second.load(); try await second.save()
            let reference=try await after.reference(itemId:item.id); XCTAssertEqual(reference?.amount,680.12)
            XCTAssertFalse(second.hasChanges); XCTAssertNil(defaults.data(forKey:second.draftKey))
        }
        let order=try await Self.purchase(item,orders)
        for mode in [FinanceEditorMode.refund(order.id),.cancel(order.id)] {
            let first=FinanceEditorViewModel(mode:mode,afterSale:after,orders:orders,finance:finance,defaults:defaults)
            await first.load(); first.draft.amount="25.25"; first.draft.confirmed=true; first.persist()
            let second=FinanceEditorViewModel(mode:mode,afterSale:after,orders:orders,finance:finance,defaults:defaults)
            await second.load(); try await second.save()
            XCTAssertFalse(second.hasChanges); XCTAssertNil(defaults.data(forKey:second.draftKey))
        }
        let final=try await orders.get(order.id); XCTAssertEqual(final.refundedAmount,25.25); XCTAssertNotNil(final.cancellation)
    }

    func testReferenceCannotBecomeHiddenByChangingToSharedChild() async throws {
        let (q,item,_,after,_) = try await Self.setup()
        let parent=try await ItemRepository(db:q).insert(Item(name:"主件",brandId:item.brandId,categoryId:item.categoryId))
        try await after.saveReference(itemId:item.id,amount:0,note:"明确零元",expected:nil)
        var changed=item; changed.parentItemId=parent.id; changed.includedInParentPrice=true
        let submitted=changed
        await fails { try await ItemRepository(db:q).update(submitted) }
        let stored=try await ItemRepository(db:q).getById(item.id)
        XCTAssertFalse(stored?.includedInParentPrice == true)
        let reference=try await after.reference(itemId:item.id)
        let prices=OrderAccounting.displayAmounts(prices:[],bindings:[],stages:[],references:[reference!])
        XCTAssertEqual(prices[item.id],0); XCTAssertEqual(lolitaPriceLabel(0),"¥0.00")
    }
    func testCancelledWishRemainsReachableFromActualPaymentPeriod() async throws {
        let (q,item,orders,after,_) = try await Self.setup(); let order=try await Self.purchase(item,orders)
        try await after.cancelOrder(priceId:order.id,expectedRefund:nil,note:"",expected:order.fingerprint,confirmed:true)
        let wished=try await ItemRepository(db:q).getById(item.id)
        let rows=StatsItemFilter.paymentPeriod("2026-01").apply(to:[wished!],brands:[],categories:[],prices:[order.price],payments:order.payments)
        XCTAssertEqual(rows.map(\.id),[item.id])
    }

    func testBudgetMathUsesCentsAndRevisionOverflowIsRejected() async throws {
        let (q,item,_,after,finance) = try await Self.setup()
        let date=Date(timeIntervalSince1970:1769904000)
        let snapshot=FinanceSnapshot(entries:[FinanceEntry(id:"paid",itemName:"",priceId:1,amount:13.3,date:1769904000000,isPaid:true),FinanceEntry(id:"pending",itemName:"",priceId:1,amount:42.11,date:1769904000000,isPaid:false)],budgets:[MonthlyBudget(month:FinanceSnapshot.monthKey(date),amountCents:10001)])
        XCTAssertEqual(snapshot.month(date).projectedRemaining,44.6)
        try await after.saveReference(itemId:item.id,amount:0,note:"",expected:nil)
        try await q.write { db in try db.execute(sql:"UPDATE itemReferencePrices SET revision = ?",arguments:[Int64.max]) }
        let old=try await after.reference(itemId:item.id)
        await fails { try await after.saveReference(itemId:item.id,amount:1,note:"",expected:old) }
        await fails { try await finance.saveBudget(month:"2026-02",amount:Double.leastNonzeroMagnitude,expected:nil) }
    }

}
