import XCTest
@preconcurrency import GRDB
@testable import lolita

final class OrderLedgerRegressionTests: XCTestCase {
    private static func item(_ db: Database, status: ItemStatus = .owned) throws -> Item {
        var brand = Brand(name: UUID().uuidString); try brand.insert(db)
        var category = Category(name: UUID().uuidString); try category.insert(db)
        var item = Item(name: "裙子", brandId: brand.id, categoryId: category.id, status: status, createdAt: 123, updatedAt: 456)
        try item.insert(db); return item
    }
    private static func setup(status: ItemStatus = .owned) async throws -> (DatabaseQueue, Item, OrderRepository) {
        let queue = try LolitaDatabase(path: ":memory:").dbQueue
        let item = try await queue.write { @Sendable db in try Self.item(db, status: status) }
        return (queue, item, OrderRepository(db: queue))
    }

    func testV4MigrationPreservesEveryOldColumnAndIsIdempotent() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let old = try LolitaDatabase(path: path, migrationTarget: "v4-import-order-keys")
        let tables = ["brands", "categories", "styles", "seasons", "sources", "locations", "coordinates", "items", "prices", "payments", "outfitLogs", "outfitItemCrossRef"]
        let before: [String: [Row]] = try old.dbQueue.write { db in
            try PresetData.seed(db)
            try db.execute(sql: "INSERT INTO locations(id,name,description,sortOrder,createdAt,updatedAt,imageUrl) VALUES(9,'衣柜','原位置',2,3,4,'old-room.jpg')")
            try db.execute(sql: "INSERT INTO coordinates(id,name,description,imageUrls,createdAt,updatedAt) VALUES(9,'套装','原描述','[\"old.jpg\"]',1,2)")
            let brand = try Int64.fetchOne(db, sql: "SELECT id FROM brands LIMIT 1")!
            let category = try Int64.fetchOne(db, sql: "SELECT id FROM categories LIMIT 1")!
            for id in 1...4 {
                try db.execute(sql: """
                    INSERT INTO items(id,name,brandId,categoryId,status,description,imageUrls,sizeChartImageUrl,coordinateId,locationId,importOrderKeys,createdAt,updatedAt)
                    VALUES(?, ?, ?, ?, ?, '原描述', '["old.jpg"]', 'size.jpg',9,9,'["tb-key"]',123,456)
                    """, arguments: [id, "旧物品\(id)", brand, category, id == 3 ? "WISHED" : "OWNED"])
            }
            for (id, item, total) in [(1,1,300.0),(2,2,200.0),(3,2,500.0),(4,3,100.0),(5,4,12.345)] {
                try db.execute(sql: "INSERT INTO prices(id,itemId,type,totalPrice,createdAt) VALUES(?,?,'FULL',?,777)", arguments: [id,item,total])
            }
            try db.execute(sql: "INSERT INTO payments(id,priceId,amount,dueDate,isPaid,paidDate,calendarEventId,reminderSet,customReminderDays,createdAt) VALUES(11,1,100,111,1,NULL,998,1,3,999),(12,1,200,222,0,NULL,997,1,2,888)")
            try db.execute(sql: "INSERT INTO outfitLogs(id,date,note,imageUrls,createdAt,updatedAt) VALUES(1,321,'原穿搭','[\"old.jpg\"]',3,4)")
            try db.execute(sql: "INSERT INTO outfitItemCrossRef(outfitLogId,itemId) VALUES(1,1)")
            return try Dictionary(uniqueKeysWithValues: tables.map { ($0, try Row.fetchAll(db, sql: "SELECT * FROM \($0)")) })
        }
        try old.dbQueue.close()
        let upgraded = try LolitaDatabase(path: path)
        try upgraded.dbQueue.read { db in
            for table in tables {
                let rows = before[table]!
                let columns = rows.first?.columnNames.map { "\"\($0)\"" }.joined(separator: ",") ?? "*"
                XCTAssertEqual(try Row.fetchAll(db, sql: "SELECT \(columns) FROM \(table)"), rows, table)
            }
            let binding = try XCTUnwrap(OrderBinding.fetchOne(db, key: 1))
            XCTAssertEqual(binding.purchaseRecordStatus, .historicalOwned)
            XCTAssertNil(try OrderBinding.fetchOne(db, key: 2), "多个旧价格不猜选当前订单")
            XCTAssertNil(try OrderBinding.fetchOne(db, key: 3), "心愿报价不变成购买")
            XCTAssertNil(try OrderBinding.fetchOne(db, key: 4), "历史精度异常保留原金额并待核对")
            XCTAssertEqual(try PaymentStage.fetchCount(db), 2)
            XCTAssertNil(try Payment.fetchOne(db, key: 11)?.paidDate)
            XCTAssertTrue(try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty)
        }
        try upgraded.dbQueue.close()
        let reopened = try LolitaDatabase(path: path)
        XCTAssertEqual(try reopened.dbQueue.read { try PaymentStage.fetchCount($0) }, 2)
        try reopened.dbQueue.close()
    }

    func testNewOrderDoesNotInventPaymentOrDateAndUndatedDebtIsCounted() async throws {
        let (queue, item, repo) = try await Self.setup(status: .wished)
        let price = try await repo.create(price: Price(itemId: item.id, type: .full, totalPrice: 100, shipping: 10), stages: [PaymentStage(name: "全款", amount: 100)])
        let order = try await repo.get(price.id)
        XCTAssertTrue(order.payments.isEmpty)
        XCTAssertNil(order.stages.first?.dueDate)
        XCTAssertEqual(order.remainingAmount, 100)
        let status = try await queue.read { @Sendable db in try Item.fetchOne(db, key: item.id)?.status }
        XCTAssertEqual(status, .pendingPayment)
        var iterator = PaymentRepository(db: queue).getTotalUnpaidAmount().makeAsyncIterator()
        let total = await iterator.next(); XCTAssertEqual(total, 100)
        let reminders = try await PaymentRepository(db: queue).getReminderRecords()
        XCTAssertTrue(reminders.isEmpty)
        do { _ = try await repo.create(price: price, stages: order.stages); XCTFail("不能创建第二个当前订单") } catch {}
    }

    func testPartialPaymentsIdempotencyAndStageAllocation() async throws {
        let (_, item, repo) = try await Self.setup()
        let price = try await repo.create(price: Price(itemId: item.id, type: .multiStage, totalPrice: 300), stages: [PaymentStage(name: "一期", amount: 100), PaymentStage(name: "二期", amount: 200)])
        let initial = try await repo.get(price.id)
        let first = try await repo.recordPayment(priceId: price.id, amount: 40, paidDate: 1000, stageId: initial.stages[0].id, operationId: "once", expected: initial.fingerprint)
        let repeated = try await repo.recordPayment(priceId: price.id, amount: 40, paidDate: 1000, stageId: initial.stages[0].id, operationId: "once", expected: initial.fingerprint)
        XCTAssertEqual(first.id, repeated.id)
        _ = try await repo.recordPayment(priceId: price.id, amount: 90, paidDate: 2000)
        let after = try await repo.get(price.id)
        XCTAssertEqual(after.paidAmount, 130)
        XCTAssertEqual(after.stageRemaining[after.stages[0].id], 0)
        XCTAssertEqual(after.stageRemaining[after.stages[1].id], 170)
        for amount in [171.0, -1, 0, 1.001, Double.infinity] {
            do { _ = try await repo.recordPayment(priceId: price.id, amount: amount, paidDate: 3000); XCTFail("必须拒绝无效或超额付款 \(amount)") } catch {}
        }
        do { _ = try await repo.recordPayment(priceId: price.id, amount: 1, paidDate: 3000, expected: initial.fingerprint); XCTFail("陈旧表单不能覆盖") } catch {}
        let final = try await repo.get(price.id); XCTAssertEqual(final.payments.count, 2)
    }

    func testConcurrentPaymentsCannotExceedOrderTotal() async throws {
        let (_, item, repo) = try await Self.setup()
        let price = try await repo.create(price: Price(itemId: item.id, type: .full, totalPrice: 100), stages: [PaymentStage(name: "全款", amount: 100)])
        let successes = await withTaskGroup(of: Bool.self) { group in
            for index in 0..<12 {
                group.addTask {
                    do { _ = try await repo.recordPayment(priceId: price.id, amount: 20, paidDate: 1000, operationId: "concurrent-\(index)"); return true }
                    catch { return false }
                }
            }
            var count = 0; for await success in group { if success { count += 1 } }; return count
        }
        XCTAssertEqual(successes, 5)
        let final = try await repo.get(price.id)
        XCTAssertEqual(final.paidAmount, 100)
        XCTAssertEqual(final.remainingAmount, 0)
    }

    func testPlanChangesPreserveActualHistoryAndRejectForeignStagesAtomically() async throws {
        let (queue, item, repo) = try await Self.setup()
        let price = try await repo.create(price: Price(itemId: item.id, type: .depositBalance, totalPrice: 300, deposit: 100, balance: 200), stages: [PaymentStage(name: "定金", amount: 100), PaymentStage(name: "尾款", amount: 200)])
        var order = try await repo.get(price.id)
        let paid = try await repo.recordPayment(priceId: price.id, amount: 80, paidDate: 12345, stageId: order.stages[0].id)
        order = try await repo.get(price.id)
        var value = price; value.type = .multiStage; value.totalPrice = 350
        _ = try await repo.update(price: value, stages: [PaymentStage(name: "重新约定", amount: 350)], expected: order.fingerprint)
        let updated = try await repo.get(price.id)
        let stored = try XCTUnwrap(updated.payments.first)
        XCTAssertEqual(stored.id, paid.id); XCTAssertEqual(stored.amount, paid.amount)
        XCTAssertEqual(stored.paidDate, paid.paidDate); XCTAssertEqual(stored.createdAt, paid.createdAt)
        XCTAssertNil(stored.stageId)
        XCTAssertEqual(updated.remainingAmount, 270)
        value.totalPrice = 50
        do { _ = try await repo.update(price: value, stages: [PaymentStage(name: "错误", amount: 50)]); XCTFail("低于已付必须回滚") } catch {}
        var foreign = updated.stages[0]; foreign.id = 999999
        value.totalPrice = 350
        do { _ = try await repo.update(price: value, stages: [foreign]); XCTFail("不属于订单的阶段必须拒绝") } catch {}
        let count = try await queue.read { @Sendable db in try PaymentStage.fetchCount(db) }
        XCTAssertEqual(count, 1)
        let afterFailure = try await repo.get(price.id)
        XCTAssertEqual(afterFailure.paidAmount, 80)
    }

    func testHistoricalReviewArchiveAndRepurchaseKeepOriginalLedger() async throws {
        let (queue, item, repo) = try await Self.setup()
        let old = try await queue.write { @Sendable db in
            var price = Price(itemId: item.id, type: .full, totalPrice: 200); try price.insert(db)
            var stage = PaymentStage(priceId: price.id, name: "旧计划", amount: 200, dueDate: 1000, reminderSet: true); try stage.insert(db)
            return price
        }
        try await repo.bindHistorical(itemId: item.id, priceId: old.id)
        do { _ = try await repo.recordPayment(priceId: old.id, amount: 200, paidDate: 1); XCTFail("待核对不能新增付款") } catch {}
        try await repo.confirmPurchase(priceId: old.id, historicalOwned: true)
        let historical = try await repo.get(old.id)
        XCTAssertNil(historical.remainingAmount); XCTAssertTrue(historical.payments.isEmpty)
        let actual = try await repo.recordPayment(priceId: old.id, amount: 50, paidDate: nil)
        XCTAssertNil(actual.paidDate)
        try await repo.archive(priceId: old.id)
        let next = try await repo.create(price: Price(itemId: item.id, type: .full, totalPrice: 400), stages: [PaymentStage(name: "新购买", amount: 400)])
        let oldAgain = try await repo.get(old.id)
        XCTAssertFalse(oldAgain.isCurrent); XCTAssertEqual(oldAgain.paidAmount, 50)
        XCTAssertEqual(oldAgain.price.purchaseRecordStatus, .historicalOwned)
        do { _ = try await repo.recordPayment(priceId: old.id, amount: 1, paidDate: 1); XCTFail("归档只读") } catch {}
        XCTAssertNotEqual(old.id, next.id)
    }

    func testSharedAccessoriesFollowOwnerAndCannotDuplicateLedgerOrFormCycle() async throws {
        let (queue, item, repo) = try await Self.setup()
        var child = Item(name: "配套蝴蝶结", brandId: item.brandId, categoryId: item.categoryId, parentItemId: item.id, includedInParentPrice: true)
        child = try await ItemRepository(db: queue).insert(child)
        let price = try await repo.create(price: Price(itemId: item.id, type: .full, totalPrice: 100), stages: [PaymentStage(name: "全款", amount: 100)])
        let childId = child.id
        let pending = try await queue.read { @Sendable db in try Item.fetchOne(db, key: childId)?.status }
        XCTAssertEqual(pending, .pendingPayment)
        do { _ = try await repo.create(price: Price(itemId: child.id, type: .full, totalPrice: 100), stages: [PaymentStage(name: "错误", amount: 100)]); XCTFail("共价不可再建单") } catch {}
        _ = try await repo.recordPayment(priceId: price.id, amount: 100, paidDate: 1000)
        let owned = try await queue.read { @Sendable db in try Item.fetchOne(db, key: childId)?.status }
        XCTAssertEqual(owned, .owned)
        var cycle = item; cycle.parentItemId = child.id
        do { try await ItemRepository(db: queue).update(cycle); XCTFail("循环主件拒绝") } catch {}
        do { try await ItemRepository(db: queue).delete(item); XCTFail("关联小物不能被级联误删") } catch {}
        var iterator = repo.observe(itemId: child.id).makeAsyncIterator()
        let shared = await iterator.next(); XCTAssertEqual(shared?.map(\.id), [price.id])
        let priceCount = try await queue.read { @Sendable db in try Price.fetchCount(db) }
        XCTAssertEqual(priceCount, 1)
        let coordinate = try await CoordinateRepository(db: queue).save(Coordinate(name: "共价套装", description: ""), itemIds: [item.id, child.id])
        let total = try await PriceRepository(db: queue).getTotalByCoordinate(coordinate.id)
        XCTAssertEqual(total, 100, "主件与共价小物只计价一次")
    }

    func testCalendarAndRemindersUseRemainingStagesAndKeepArchivedActualDates() async throws {
        let (queue, item, repo) = try await Self.setup()
        let price = try await repo.create(price: Price(itemId: item.id, type: .full, totalPrice: 300), stages: [PaymentStage(name: "全款", amount: 300, dueDate: 5000, reminderSet: true)])
        _ = try await repo.recordPayment(priceId: price.id, amount: 100, paidDate: 2000)
        let paymentRepo = PaymentRepository(db: queue)
        let records = try await paymentRepo.getReminderRecords()
        XCTAssertEqual(records.filter { !$0.isPaid }.map(\.amount), [200])
        XCTAssertTrue(records.contains { $0.isPaid && $0.dueDate == 2000 })
        XCTAssertTrue(records.contains { $0.paymentId < 0 && $0.dueDate == 5000 })
        let stage = try await repo.get(price.id).stages[0]
        XCTAssertEqual(AppDeepLink.parse(URL(string: "lolita://stage/\(stage.id)")!), .payment(-stage.id))
        try await repo.archive(priceId: price.id)
        let archived = try await paymentRepo.getReminderRecords()
        XCTAssertFalse(archived.contains { !$0.isPaid })
        XCTAssertEqual(archived.filter(\.isPaid).map(\.amount), [100])
    }

    func testLedgerBackupJSONZIPCSVAndCorruptRelationships() async throws {
        let (queue, item, repo) = try await Self.setup()
        let image = try XCTUnwrap(ImageFileHelper.save(imageData: Data([1, 4, 9, 16])))
        defer { ImageFileHelper.delete(path: image) }
        try await queue.write { @Sendable db in try db.execute(sql: "UPDATE items SET imageUrls = ? WHERE id = ?", arguments: [StringList([image]), item.id]) }
        let price = try await repo.create(price: Price(itemId: item.id, type: .full, totalPrice: 123.45, shipping: 3.45), stages: [PaymentStage(name: "全款", amount: 123.45, dueDate: 9000, reminderSet: true)])
        _ = try await repo.recordPayment(priceId: price.id, amount: 23.45, paidDate: 5000, operationId: "backup-payment")
        _ = try await ItemRepository(db: queue).insert(Item(name: "共价配套", brandId: item.brandId, categoryId: item.categoryId, parentItemId: item.id, includedInParentPrice: true))
        let manager = BackupManager(db: queue)
        let original = try await manager.snapshot()
        let json = try await manager.exportJSON()
        var preview = try BackupManager.preview(json)
        preview.items.reverse()
        XCTAssertEqual(preview.orderBindings.count, 1); XCTAssertEqual(preview.paymentStages.count, 1)
        let target = try LolitaDatabase(path: ":memory:").dbQueue
        let targetManager = BackupManager(db: target)
        try await targetManager.restore(preview)
        let restored = try await targetManager.snapshot()
        for path in restored.imagePaths where ImageFileHelper.isOwnedFile(path) { ImageFileHelper.delete(path: path) }
        XCTAssertEqual(restored.payments.first?.operationId, "backup-payment")
        XCTAssertEqual(restored.orderBindings, original.orderBindings)
        XCTAssertEqual(restored.prices.first?.shipping, 3.45)
        XCTAssertEqual(restored.items.first(where: { $0.includedInParentPrice })?.parentItemId, item.id)
        XCTAssertFalse(restored.paymentStages.first?.reminderSet == true)
        let zip = try await manager.exportZIP()
        let zipURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        defer { try? FileManager.default.removeItem(at: zipURL) }
        try zip.write(to: zipURL)
        let prepared = try BackupManager.prepare(at: zipURL)
        try await targetManager.restore(prepared)
        let zipped = try await targetManager.snapshot()
        for path in zipped.imagePaths where ImageFileHelper.isOwnedFile(path) { defer { ImageFileHelper.delete(path: path) }; XCTAssertEqual(try Data(contentsOf: ImageFileHelper.fileURL(for: path)), Data([1, 4, 9, 16])) }
        XCTAssertEqual(zipped.payments.first?.paidDate, 5000)
        let csv = String(decoding: try await manager.exportCSV(), as: UTF8.self)
        XCTAssertTrue(csv.contains("=== ORDER_BINDINGS ===")); XCTAssertTrue(csv.contains("=== PAYMENT_STAGES ==="))
        var broken = preview; broken.payments[0].stageId = 99999
        do { try await targetManager.restore(broken); XCTFail("拒绝悬空阶段引用") } catch {}
        let afterFailure = try await targetManager.snapshot(); XCTAssertEqual(afterFailure.payments.count, 1)
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        root.removeValue(forKey: "paymentStages")
        XCTAssertThrowsError(try BackupManager.preview(JSONSerialization.data(withJSONObject: root)))
    }

    func testLegacyBackupRestoreBuildsPlansWithoutGuessingUnknownDates() async throws {
        let root: [String: Any] = [
            "brands": [["id": 1, "name": "旧品牌"]], "categories": [["id": 1, "name": "旧分类"]],
            "items": [["id": 1, "name": "原服饰", "brandId": 1, "categoryId": 1, "status": "OWNED", "createdAt": 111, "updatedAt": 222]],
            "prices": [["id": 5, "itemId": 1, "type": "FULL", "totalPrice": 300]],
            "payments": [["id": 7, "priceId": 5, "amount": 50, "dueDate": 999, "isPaid": true]],
            "formatVersion": 1
        ]
        let preview = try BackupManager.preview(JSONSerialization.data(withJSONObject: root))
        XCTAssertNil(preview.iosLedgerVersion)
        let queue = try LolitaDatabase(path: ":memory:").dbQueue
        let manager = BackupManager(db: queue)
        try await manager.restore(preview)
        let restored = try await manager.snapshot()
        XCTAssertEqual(restored.orderBindings.first?.purchaseRecordStatus, .historicalOwned)
        XCTAssertEqual(restored.payments.first?.id, 7)
        XCTAssertEqual(restored.payments.first?.amount, 50)
        XCTAssertNil(restored.payments.first?.paidDate)
        XCTAssertEqual(restored.payments.first?.dueDate, 999)
        XCTAssertEqual(restored.items.first?.updatedAt, 222)
        XCTAssertEqual(restored.paymentStages.count, 1)
        XCTAssertEqual(restored.iosLedgerVersion, 2)
    }

    func testSpendingUsesActualPaymentsAcrossOwnershipAndArchiveAndUnknownDatesStayOutOfTrend() async throws {
        let (queue, item, repo) = try await Self.setup()
        let price = try await repo.create(price: Price(itemId: item.id, type: .full, totalPrice: 300), stages: [PaymentStage(name: "计划", amount: 300)])
        _ = try await repo.recordPayment(priceId: price.id, amount: 100, paidDate: 0)
        try await repo.archive(priceId: price.id)
        let next = try await repo.create(price: Price(itemId: item.id, type: .full, totalPrice: 500), stages: [PaymentStage(name: "新计划", amount: 500)])
        _ = try await repo.recordPayment(priceId: next.id, amount: 50, paidDate: 1000)
        let displayed = try await queue.read { @Sendable db in
            OrderAccounting.displayAmounts(prices: try Price.fetchAll(db), bindings: try OrderBinding.fetchAll(db), stages: try PaymentStage.fetchAll(db))
        }
        XCTAssertEqual(displayed[item.id], 500, "原购买金额不能叠加到当前订单上")
        let prices = PriceRepository(db: queue)
        var total = prices.getTotalSpending().makeAsyncIterator()
        let spent = await total.next(); XCTAssertEqual(spent, 150, "不按订单报价或拥有状态推断消费")
        var brands = prices.getSpendingByBrand().makeAsyncIterator()
        let byBrand = await brands.next(); XCTAssertEqual(byBrand?.first?.totalSpending, 150)
        var trend = prices.getMonthlySpending().makeAsyncIterator()
        let monthly = await trend.next(); XCTAssertEqual(monthly?.reduce(0) { $0 + $1.totalSpending }, 150)
        try await repo.confirmPurchase(priceId: next.id, historicalOwned: true)
        _ = try await repo.recordPayment(priceId: next.id, amount: 20, paidDate: nil)
        var unknownTrend = prices.getMonthlySpending().makeAsyncIterator()
        let withoutUnknown = await unknownTrend.next(); XCTAssertEqual(withoutUnknown?.reduce(0) { $0 + $1.totalSpending }, 150)
        var allKnownMoney = prices.getTotalSpending().makeAsyncIterator()
        let includingUnknownDate = await allKnownMoney.next(); XCTAssertEqual(includingUnknownDate, 170)
    }

    @MainActor
    func testPaymentEditorSnapshotsInputAndRejectsConcurrentLedgerChange() async throws {
        let (queue, item, repo) = try await Self.setup()
        let price = try await repo.create(price: Price(itemId: item.id, type: .full, totalPrice: 300), stages: [PaymentStage(name: "全款", amount: 300)])
        let editor = PaymentEditViewModel(priceId: price.id, repository: PaymentRepository(db: queue))
        await editor.load()
        XCTAssertTrue(editor.isOrderPayment)
        XCTAssertTrue(editor.isPaid)
        editor.amountText = "80"
        _ = try await repo.recordPayment(priceId: price.id, amount: 50, paidDate: 1000)
        do { _ = try await editor.save(); XCTFail("并发更改后必须重新核对") } catch {}
        XCTAssertEqual(editor.amountText, "80")
        XCTAssertTrue(editor.hasChanges)
        let order = try await repo.get(price.id)
        XCTAssertEqual(order.payments.count, 1)
        XCTAssertEqual(order.paidAmount, 50)
    }

    @MainActor
    func testLegacyPlanLinkRecordsNewActualWithoutChangingOriginalRow() async throws {
        let (queue, item, repo) = try await Self.setup()
        let price = try await repo.create(price: Price(itemId: item.id, type: .full, totalPrice: 100), stages: [PaymentStage(name: "原计划", amount: 100)])
        let order = try await repo.get(price.id)
        let legacy = try await queue.write { @Sendable db in
            var record = Payment(priceId: price.id, amount: 100, dueDate: 999, stageId: order.stages[0].id)
            try record.insert(db); return record
        }
        let editor = PaymentEditViewModel(priceId: price.id, paymentId: legacy.id, repository: PaymentRepository(db: queue))
        await editor.load()
        XCTAssertNil(editor.paymentId)
        XCTAssertTrue(editor.amountText.isEmpty)
        editor.amountText = "40"
        _ = try await editor.save()
        let after = try await repo.get(price.id)
        XCTAssertEqual(after.payments.first(where: { $0.id == legacy.id })?.isPaid, false)
        XCTAssertEqual(after.payments.filter(\.isPaid).map(\.amount), [40])
        XCTAssertEqual(after.remainingAmount, 60)
    }

    @MainActor
    func testLegacyFullOrderWithSeveralStagesCanBeEditedWithoutDuplicatingTotal() async throws {
        let (queue, item, repo) = try await Self.setup()
        let price = try await repo.create(price: Price(itemId: item.id, type: .full, totalPrice: 300), stages: [PaymentStage(name: "历史一期", amount: 100), PaymentStage(name: "历史二期", amount: 200)])
        let editor = PriceEditViewModel(itemId: item.id, priceId: price.id, repository: PriceRepository(db: queue))
        await editor.load()
        XCTAssertEqual(editor.type, .multiStage)
        try await editor.save()
        let after = try await repo.get(price.id)
        XCTAssertEqual(after.stages.map(\.amount), [100, 200])
        XCTAssertTrue(after.payments.isEmpty)
        XCTAssertEqual(after.price.totalPrice, 300)
    }

    func testLegacyNullPurchaseDateDoesNotInventPaidMoneyAndArchivedAPIsStayReadOnly() async throws {
        let root: [String: Any] = ["brands": [["id": 1, "name": "品牌"]], "categories": [["id": 1, "name": "分类"]],
            "items": [["id": 1, "name": "物品", "brandId": 1, "categoryId": 1]],
            "prices": [["id": 1, "itemId": 1, "type": "FULL", "totalPrice": 100, "purchaseDate": NSNull()]]]
        let preview = try BackupManager.preview(JSONSerialization.data(withJSONObject: root))
        XCTAssertTrue(preview.payments.isEmpty)
        let (queue, item, repo) = try await Self.setup()
        let price = try await repo.create(price: Price(itemId: item.id, type: .full, totalPrice: 100), stages: [PaymentStage(name: "全款", amount: 100)])
        let actual = try await repo.recordPayment(priceId: price.id, amount: 20, paidDate: 1000)
        try await repo.archive(priceId: price.id)
        do { _ = try await PaymentRepository(db: queue).insert(Payment(priceId: price.id, amount: 10, dueDate: 1, isPaid: true, paidDate: 1)); XCTFail("旧入口不能向归档单增记") } catch {}
        do { try await PaymentRepository(db: queue).delete(actual); XCTFail("旧入口不能删除归档实付") } catch {}
        do { try await PriceRepository(db: queue).delete(price); XCTFail("旧入口不能删除历史账本") } catch {}
        let after = try await repo.get(price.id)
        XCTAssertEqual(after.payments.count, 1)
        XCTAssertEqual(after.paidAmount, 20)
    }

    func testCentArithmeticRejectsFractionalCentsAndOverflow() throws {
        XCTAssertEqual(try OrderAccounting.sum([0.1, 0.2]), 0.3)
        XCTAssertThrowsError(try OrderAccounting.validate(1.001))
        XCTAssertThrowsError(try OrderAccounting.validate(.nan))
        XCTAssertThrowsError(try OrderAccounting.validate(90_000_000_000_000))
        XCTAssertThrowsError(try OrderAccounting.sum(Array(repeating: 89_000_000_000_000, count: 2000)))
    }
}
