import XCTest
import GRDB
@testable import lolita

final class PaymentYearRegressionTests: XCTestCase {
    private func calendar(_ zone: String) -> Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: zone)!; return c }
    private func date(_ text: String) -> Int64 { Int64(ISO8601DateFormatter().date(from: text)!.timeIntervalSince1970 * 1000) }
    private func row(_ id: Int64, _ amount: Double, _ date: Int64, paid: Bool = false) -> PaymentWithItemInfo {
        PaymentWithItemInfo(paymentId: id, amount: amount, dueDate: date, isPaid: paid, priceId: 1, priceType: "FULL", itemName: "旧服饰", itemId: 1)
    }
    func testLocalYearRangeIsHalfOpenAcrossLeapYearAndTimeZone() {
        let range = PaymentYearSnapshot.range(year: 2024, calendar: calendar("Asia/Shanghai"))
        XCTAssertEqual(range.lowerBound, date("2023-12-31T16:00:00Z"))
        XCTAssertEqual(range.upperBound, date("2024-12-31T16:00:00Z"))
        XCTAssertTrue(range.contains(range.upperBound - 1)); XCTAssertFalse(range.contains(range.upperBound))
        let la = PaymentYearSnapshot.range(year: 2026, calendar: calendar("America/Los_Angeles"))
        XCTAssertEqual(la.lowerBound, date("2026-01-01T08:00:00Z"))
        XCTAssertEqual(la.upperBound, date("2027-01-01T08:00:00Z"))
    }
    func testMonthGroupingUsesLocalDateAndOverdueChangesWithoutDatabaseWrite() {
        let boundary = date("2026-01-31T16:00:00Z")
        let rows = [row(1, 0.1, boundary, paid: true), row(2, 0.2, boundary, paid: true), row(-3, 12.34, boundary)]
        let before = PaymentYearSnapshot(payments: rows, calendar: calendar("Asia/Shanghai"), now: boundary)
        XCTAssertTrue(before.month(1).isEmpty); XCTAssertEqual(before.month(2).count, 3)
        XCTAssertEqual(before.paid(rows), 0.3); XCTAssertEqual(before.pending(rows), 12.34)
        XCTAssertEqual(before.overdue(rows), 0)
        let after = PaymentYearSnapshot(payments: rows, calendar: before.calendar, now: boundary + 1)
        XCTAssertEqual(after.overdue(rows), 12.34)
        XCTAssertEqual(PaymentYearSnapshot(payments: rows, calendar: calendar("UTC"), now: boundary).month(1).count, 3)
    }
    @MainActor
    func testSelectionTogglesYearChangeClearsAndZoneChangeReplacesObservationKey() throws {
        let db = try LolitaDatabase(path: ":memory:")
        let vm = PaymentYearViewModel(repository: PaymentRepository(db: db.dbQueue), calendar: calendar("Asia/Shanghai"), date: Date(timeIntervalSince1970: Double(date("2026-06-01T00:00:00Z")) / 1000))
        vm.selectMonth(2); XCTAssertEqual(vm.selectedMonth, 2)
        vm.selectMonth(2); XCTAssertNil(vm.selectedMonth)
        vm.selectMonth(12); vm.changeYear(-1); XCTAssertEqual(vm.year, 2025); XCTAssertNil(vm.selectedMonth)
        let key = vm.observationKey
        vm.refreshTime(calendar: calendar("America/Los_Angeles"))
        XCTAssertNotEqual(vm.observationKey, key); XCTAssertEqual(vm.year, 2025)
    }
    func testProjectedRowsUseActualDateKeepArchivedAndOmitUnknownDatesWithoutRewritingHistory() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        let jan = date("2026-01-20T12:00:00Z"), feb = date("2026-02-20T12:00:00Z")
        try await database.dbQueue.write { @Sendable db in
            var brand = Brand(id: 1, name: "旧品牌"); try brand.insert(db)
            var category = Category(id: 1, name: "旧分类"); try category.insert(db)
            var item = Item(id: 1, name: "旧衣", brandId: 1, categoryId: 1); try item.insert(db)
            var price = Price(id: 1, itemId: 1, type: .full, totalPrice: 100); try price.insert(db)
            var actual = Payment(id: 1, priceId: 1, amount: 20, dueDate: jan, isPaid: true, paidDate: feb); try actual.insert(db)
            var unknown = Payment(id: 2, priceId: 1, amount: 10, dueDate: jan, isPaid: true); try unknown.insert(db)
        }
        let rows = try await database.dbQueue.read { @Sendable db in try PaymentRepository.projected(db) }
        XCTAssertEqual(rows.count, 1); XCTAssertEqual(rows.first?.dueDate, feb)
        let stored = try await database.dbQueue.read { @Sendable db in try Payment.fetchAll(db) }
        XCTAssertEqual(stored.map(\.dueDate), [jan, jan]); XCTAssertNil(stored[1].paidDate)
    }
    @MainActor
    func testYearObservationUpdatesPartialRemainingAndCancelsBeforeYearSwitch() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        try await database.dbQueue.write { @Sendable db in
            var brand = Brand(id: 1, name: "品牌"); try brand.insert(db)
            var category = Category(id: 1, name: "分类"); try category.insert(db)
            var item = Item(id: 1, name: "分段订单", brandId: 1, categoryId: 1); try item.insert(db)
        }
        let price = try await PriceRepository(db: database.dbQueue).saveWithPayments(Price(itemId: 1, type: .full, totalPrice: 100))
        let due = date("2026-02-01T12:00:00Z")
        try await database.dbQueue.write { @Sendable db in try db.execute(sql: "UPDATE paymentStages SET dueDate=?", arguments: [due]) }
        let repo = PaymentRepository(db: database.dbQueue)
        let vm = PaymentYearViewModel(repository: repo, calendar: calendar("UTC"), date: Date(timeIntervalSince1970: Double(due) / 1000))
        let task = Task { await vm.observe() }; defer { task.cancel() }
        for _ in 0..<100 { if vm.payments.count == 1 { break }; try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(vm.snapshot.pending(vm.payments), 100)
        _ = try await repo.saveActual(Payment(priceId: price.id, amount: 25.25, dueDate: due, isPaid: true, paidDate: due), expected: nil)
        for _ in 0..<100 { if vm.payments.count == 2 { break }; try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(vm.snapshot.pending(vm.payments), 74.75); XCTAssertEqual(vm.snapshot.paid(vm.payments), 25.25)
        task.cancel(); await task.value
        vm.changeYear(1)
        try await database.dbQueue.write { @Sendable db in try db.execute(sql: "UPDATE payments SET amount=30") }
        try await Task.sleep(for: .milliseconds(30)); XCTAssertTrue(vm.payments.isEmpty)
    }
}
