import XCTest
import GRDB
@testable import lolita

final class DatabaseRegressionTests: XCTestCase {
    private func database() throws -> LolitaDatabase {
        try LolitaDatabase(path: ":memory:")
    }

    private static func item(in db: Database, status: ItemStatus = .owned) throws -> Item {
        var brand = Brand(name: UUID().uuidString)
        try brand.insert(db)
        var category = Category(name: UUID().uuidString)
        try category.insert(db)
        var item = Item(name: "测试服饰", brandId: brand.id, categoryId: category.id, status: status,
                        colors: StringList(["白色", "粉色"]), imageUrls: StringList(["test.jpg"]))
        try item.insert(db)
        return item
    }

    func testPresetsAreCompleteAndIdempotent() throws {
        let db = try database()
        try db.dbQueue.write { db in
            try PresetData.seed(db)
            try PresetData.seed(db)
            XCTAssertEqual(try Brand.fetchCount(db), PresetData.brands.count)
            XCTAssertEqual(try Category.fetchCount(db), PresetData.categories.count)
            XCTAssertEqual(try Style.fetchCount(db), PresetData.styles.count)
            XCTAssertEqual(try Season.fetchCount(db), PresetData.seasons.count)
            XCTAssertEqual(try Source.fetchCount(db), 4)
            XCTAssertTrue(try Brand.fetchAll(db).allSatisfy { $0.id > 0 })
        }
    }

    func testConsecutiveInsertAndImageRoundTrip() throws {
        let database = try database()
        try write(database.dbQueue) { db in
            let first = try Self.item(in: db)
            let second = try Self.item(in: db)
            XCTAssertGreaterThan(first.id, 0)
            XCTAssertGreaterThan(second.id, first.id)
            let stored = try XCTUnwrap(Item.fetchOne(db, key: first.id))
            XCTAssertEqual(stored.colors.values, ["白色", "粉色"])
            XCTAssertEqual(stored.imageUrls.values, ["test.jpg"])
        }
    }

    func testPendingBalanceTransitionsAndWishlistPreserved() async throws {
        let database = try database()
        let item = try write(database.dbQueue) { db in try Self.item(in: db) }
        let priceRepo = PriceRepository(db: database.dbQueue)
        let paymentRepo = PaymentRepository(db: database.dbQueue)
        let price = try await priceRepo.insert(Price(itemId: item.id, type: .depositBalance, totalPrice: 1, deposit: 100, balance: 200))
        XCTAssertGreaterThan(price.id, 0)
        XCTAssertEqual(price.totalPrice, 300)
        var payment = try await paymentRepo.insert(Payment(priceId: price.id, amount: 200, dueDate: 0))
        XCTAssertGreaterThan(payment.id, 0)
        XCTAssertEqual(try read(database.dbQueue) { try Item.fetchOne($0, key: item.id)?.status }, .pendingBalance)
        payment.isPaid = true
        try await paymentRepo.update(payment)
        XCTAssertEqual(try read(database.dbQueue) { try Item.fetchOne($0, key: item.id)?.status }, .owned)
        payment.isPaid = false
        try await paymentRepo.update(payment)
        try await priceRepo.delete(price)
        XCTAssertEqual(try read(database.dbQueue) { try Item.fetchOne($0, key: item.id)?.status }, .owned)
        XCTAssertEqual(try read(database.dbQueue) { try Payment.fetchCount($0) }, 0)
        let wished = try write(database.dbQueue) { db in try Self.item(in: db, status: .wished) }
        let wishedPrice = try await priceRepo.insert(Price(itemId: wished.id, type: .depositBalance, totalPrice: 10, deposit: 0, balance: 10))
        _ = try await paymentRepo.insert(Payment(priceId: wishedPrice.id, amount: 10, dueDate: 0))
        XCTAssertEqual(try read(database.dbQueue) { try Item.fetchOne($0, key: wished.id)?.status }, .wished)
    }

    func testMonthRangeIncludesLastDayAndExcludesNextMonth() async throws {
        let database = try database()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let month = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        let range = PaymentMonthRange(month: month, calendar: calendar)
        let item = try write(database.dbQueue) { db in try Self.item(in: db) }
        let price = try await PriceRepository(db: database.dbQueue).insert(Price(itemId: item.id, type: .full, totalPrice: 100))
        let repo = PaymentRepository(db: database.dbQueue)
        _ = try await repo.insert(Payment(priceId: price.id, amount: 10, dueDate: range.end - 1))
        _ = try await repo.insert(Payment(priceId: price.id, amount: 20, dueDate: range.end))
        var iterator = repo.getByDateRange(start: range.start, end: range.end).makeAsyncIterator()
        let payments = await iterator.next()
        XCTAssertEqual(payments?.count, 1)
        XCTAssertEqual(payments?.first?.amount, 10)
    }

    func testWishlistCountsItemsRatherThanPriceRows() async throws {
        let database = try database()
        let item = try write(database.dbQueue) { db in try Self.item(in: db, status: .wished) }
        let repo = PriceRepository(db: database.dbQueue)
        _ = try await repo.insert(Price(itemId: item.id, type: .full, totalPrice: 100))
        _ = try await repo.insert(Price(itemId: item.id, type: .full, totalPrice: 200))
        var iterator = repo.getWishlistByPriorityStats().makeAsyncIterator()
        let stats = await iterator.next()
        XCTAssertEqual(stats?.first?.itemCount, 1)
        XCTAssertEqual(stats?.first?.totalBudget, 300)
    }

    func testStyleRenameAndRemovalUpdateReferences() async throws {
        let database = try database()
        var style = try await StyleRepository(db: database.dbQueue).insert(Style(name: "甜美"))
        let item = try write(database.dbQueue) { db in
            var item = try Self.item(in: db)
            item.style = "甜美"
            try item.update(db)
            return item
        }
        let repo = StyleRepository(db: database.dbQueue)
        style.name = "甜系"
        try await repo.update(style)
        XCTAssertEqual(try read(database.dbQueue) { try Item.fetchOne($0, key: item.id)?.style }, "甜系")
        try await repo.delete(style)
        XCTAssertNil(try read(database.dbQueue) { try Item.fetchOne($0, key: item.id)?.style })
    }

    func testOutfitAssociationFailureRollsBackLog() async throws {
        let database = try database()
        let repo = OutfitLogRepository(db: database.dbQueue)
        do {
            _ = try await repo.save(OutfitLog(date: 0, note: "测试"), itemIds: [999])
            XCTFail("Invalid foreign key must fail")
        } catch { }
        XCTAssertEqual(try read(database.dbQueue) { try OutfitLog.fetchCount($0) }, 0)
    }

    func testCoordinateDeleteDetachesItemsAndPreservesClothing() async throws {
        let database = try database()
        let item = try write(database.dbQueue) { db in try Self.item(in: db) }
        let repo = CoordinateRepository(db: database.dbQueue)
        let coordinate = try await repo.save(Coordinate(name: "套装", description: ""), itemIds: [item.id, item.id])
        XCTAssertGreaterThan(coordinate.id, 0)
        XCTAssertEqual(try read(database.dbQueue) { try Item.fetchOne($0, key: item.id)?.coordinateId }, coordinate.id)
        try await repo.delete(coordinate)
        let stored = try read(database.dbQueue) { try Item.fetchOne($0, key: item.id) }
        XCTAssertNotNil(stored)
        XCTAssertNil(stored?.coordinateId)
    }

    func testHistoricalZeroIDsAreMigratedWithoutLosingRelationships() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let old = try LolitaDatabase(path: path)
        try old.dbQueue.write { db in
            try db.execute(sql: "INSERT INTO brands(id,name,isPreset,createdAt) VALUES(0,'旧品牌',0,0)")
            try db.execute(sql: "INSERT INTO categories(id,name,isPreset,createdAt) VALUES(0,'旧分类',0,0)")
            try db.execute(sql: "INSERT INTO items(id,name,brandId,categoryId,createdAt,updatedAt) VALUES(0,'旧服饰',0,0,0,0)")
            try db.execute(sql: "INSERT INTO prices(id,itemId,type,totalPrice,createdAt) VALUES(0,0,'FULL',100,0)")
            try db.execute(sql: "INSERT INTO payments(id,priceId,amount,dueDate,createdAt) VALUES(0,0,100,0,0)")
            try db.execute(sql: "INSERT INTO outfitLogs(id,date,note,createdAt,updatedAt) VALUES(0,0,'旧穿搭',0,0)")
            try db.execute(sql: "INSERT INTO outfitItemCrossRef(outfitLogId,itemId) VALUES(0,0)")
            try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'v3-payment-status'")
        }
        try old.dbQueue.close()
        let upgraded = try LolitaDatabase(path: path)
        try upgraded.dbQueue.read { db in
            let item = try XCTUnwrap(Item.fetchAll(db).first)
            let price = try XCTUnwrap(Price.fetchAll(db).first)
            let payment = try XCTUnwrap(Payment.fetchAll(db).first)
            let log = try XCTUnwrap(OutfitLog.fetchAll(db).first)
            let cross = try XCTUnwrap(OutfitItemCrossRef.fetchAll(db).first)
            XCTAssertGreaterThan(item.id, 0)
            XCTAssertGreaterThan(item.brandId, 0)
            XCTAssertGreaterThan(item.categoryId, 0)
            XCTAssertEqual(price.itemId, item.id)
            XCTAssertEqual(payment.priceId, price.id)
            XCTAssertEqual(cross.outfitLogId, log.id)
            XCTAssertEqual(cross.itemId, item.id)
            XCTAssertEqual(try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").count, 0)
        }
        try upgraded.dbQueue.close()
    }

    @MainActor
    func testMonthSwitchIgnoresOldSubscriptionUpdates() async throws {
        let database = try database()
        let repo = PaymentRepository(db: database.dbQueue)
        let item = try write(database.dbQueue) { db in try Self.item(in: db) }
        let price = try await PriceRepository(db: database.dbQueue).insert(Price(itemId: item.id, type: .full, totalPrice: 100))
        let cal = Calendar.current
        let october = cal.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        let november = cal.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        var oldPayment = try await repo.insert(Payment(priceId: price.id, amount: 10, dueDate: Int64(october.timeIntervalSince1970 * 1000)))
        _ = try await repo.insert(Payment(priceId: price.id, amount: 20, dueDate: Int64(november.timeIntervalSince1970 * 1000)))
        let vm = PaymentCalendarViewModel(repository: repo)
        defer { vm.stopObserving() }
        vm.currentMonth = october
        vm.loadCalendar()
        for _ in 0..<100 {
            if vm.paymentsByDate.first?.payments.first?.amount == 10 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(vm.paymentsByDate.first?.payments.first?.amount, 10)
        vm.goToNextMonth()
        for _ in 0..<100 {
            if vm.paymentsByDate.first?.payments.first?.amount == 20 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(vm.paymentsByDate.first?.payments.first?.amount, 20)
        oldPayment.amount = 15
        try await repo.update(oldPayment)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(vm.paymentsByDate.first?.payments.first?.amount, 20)
        XCTAssertEqual(vm.paymentsByDate.first?.date, november)
    }

    func testAutoPaymentSchedulePreservesPaidHistoryOnPriceEdit() async throws {
        let database = try database()
        let item = try write(database.dbQueue) { db in try Self.item(in: db) }
        let repo = PriceRepository(db: database.dbQueue)
        var price = try await repo.saveWithPayments(Price(itemId: item.id, type: .depositBalance, totalPrice: 300, deposit: 100, balance: 200), initialPaidDate: 1000)
        let initial = try read(database.dbQueue) { try Payment.fetchAll($0) }
        XCTAssertEqual(initial.count, 1)
        XCTAssertEqual(try read(database.dbQueue) { try PaymentStage.fetchCount($0) }, 2)
        XCTAssertEqual(initial.filter(\.isPaid).reduce(0) { $0 + $1.amount }, 100)
        XCTAssertEqual(try read(database.dbQueue) { try Item.fetchOne($0, key: item.id)?.status }, .pendingBalance)
        price.balance = 250
        price = try await repo.saveWithPayments(price)
        let updated = try read(database.dbQueue) { try Payment.fetchAll($0) }
        XCTAssertEqual(updated.count, 1)
        XCTAssertEqual(updated.filter(\.isPaid).first?.id, initial.filter(\.isPaid).first?.id)
        XCTAssertEqual(updated.reduce(0) { $0 + $1.amount }, 100)
        XCTAssertEqual(try read(database.dbQueue) { try PaymentStage.fetchAll($0).reduce(0) { $0 + $1.amount } }, 350)
        XCTAssertEqual(price.totalPrice, 350)
        price.deposit = 0; price.balance = 50
        do { _ = try await repo.saveWithPayments(price); XCTFail("Price below paid amount must fail") } catch { }
        XCTAssertEqual(try read(database.dbQueue) { try Payment.fetchCount($0) }, 1)
    }

    func testAmountValidationRejectsBadValues() throws {
        for value in ["", "abc", "-1", "nan", "inf"] {
            XCTAssertThrowsError(try InputValidation.amount(value, label: "金额"))
        }
        XCTAssertEqual(try InputValidation.amount(" 12.50 ", label: "金额"), 12.5)
    }
}

private func read<T>(_ queue: DatabaseQueue, _ body: (Database) throws -> T) throws -> T { try queue.read(body) }
private func write<T>(_ queue: DatabaseQueue, _ body: (Database) throws -> T) throws -> T { try queue.write(body) }
