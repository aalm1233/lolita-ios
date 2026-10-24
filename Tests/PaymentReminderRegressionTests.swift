import XCTest
import GRDB
@testable import lolita

final class PaymentReminderRegressionTests: XCTestCase {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private static func record(id: Int64 = 1, due: Date = now.addingTimeInterval(3 * 86400), days: Int? = 1) -> PaymentReminderRecord {
        PaymentReminderRecord(paymentId: id, amount: 123, dueDate: Int64(due.timeIntervalSince1970 * 1000),
            isPaid: false, reminderSet: true, customReminderDays: days, createdAt: 100, itemName: "裙子")
    }

    func testPlansRespectPaidDisabledAndRequestBudget() {
        var paid = Self.record(id: 100); paid.isPaid = true
        var disabled = Self.record(id: 101); disabled.reminderSet = false
        let records = (1...70).reversed().map { Self.record(id: Int64($0)) } + [paid, disabled]
        let result = PaymentReminderPlanner.notifications(records, now: Self.now)
        XCTAssertEqual(result.count, 48)
        XCTAssertEqual(result.map(\.paymentId), (1...48).map(Int64.init))
        XCTAssertEqual(result.first?.url, "lolita://payment/1")
        XCTAssertEqual(result.first?.fireDate, Self.now.addingTimeInterval(2 * 86400))
    }

    func testPastReminderCatchesUpOnceButOldOverduePaymentsAreSkipped() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.startOfDay(for: Self.now)
        let catchup = Self.record(id: 1, due: today, days: 1)
        let old = Self.record(id: 2, due: today.addingTimeInterval(-86400), days: 1)
        let result = PaymentReminderPlanner.notifications([catchup, old], now: Self.now, calendar: calendar)
        XCTAssertEqual(result.map(\.paymentId), [1])
        XCTAssertEqual(result.first?.fireDate, Self.now.addingTimeInterval(60))
    }

    func testReminderDaysUseLocalCalendarAcrossDaylightSaving() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let due = calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 9))!
        let current = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 9))!
        let plan = PaymentReminderPlanner.notifications([Self.record(due: due, days: 2)], now: current, calendar: calendar)[0]
        XCTAssertEqual(calendar.component(.day, from: plan.fireDate), 7)
        XCTAssertEqual(calendar.component(.hour, from: plan.fireDate), 9)
        XCTAssertEqual(due.timeIntervalSince(plan.fireDate), 47 * 3600)
        XCTAssertEqual(PaymentReminderPlanner.reminderDate(due: due, days: 2, calendar: calendar), plan.fireDate)
    }

    private static func fixture(_ db: Database) throws -> Payment {
        var brand = Brand(name: "品牌"); try brand.insert(db)
        var category = Category(name: "分类"); try category.insert(db)
        var item = Item(name: "裙子", brandId: brand.id, categoryId: category.id); try item.insert(db)
        var price = Price(itemId: item.id, type: .full, totalPrice: 123); try price.insert(db)
        var payment = Payment(priceId: price.id, amount: 123,
            dueDate: Int64(Self.now.addingTimeInterval(3 * 86400).timeIntervalSince1970 * 1000),
            reminderSet: true, customReminderDays: 1)
        try payment.insert(db)
        return payment
    }

    @MainActor
    private func environment() throws -> (UserDefaults, String, FakeNotifications, FakeCalendar) {
        let suite = "PaymentReminderTests.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: suite)), suite, FakeNotifications(), FakeCalendar())
    }

    @MainActor
    func testPaidCancelsOnlyPaymentNotificationsAndCalendarEvent() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        let payment = try await database.dbQueue.write { @Sendable db in try Self.fixture(db) }
        let repo = PaymentRepository(db: database.dbQueue)
        let (defaults, suite, notifications, calendar) = try environment()
        defer { defaults.removePersistentDomain(forName: suite) }
        notifications.pending["lolita.outfit.today"] = PaymentNotificationSnapshot(identifier: "lolita.outfit.today", fingerprint: nil)
        let service = PaymentReminderService(repository: repo, defaults: defaults, notifications: notifications,
                                            calendar: calendar, now: { Self.now })
        let enableWarning = await service.setCalendarEnabled(true)
        XCTAssertNil(enableWarning)
        XCTAssertEqual(notifications.additions.count, 1)
        XCTAssertEqual(calendar.events.count, 1)
        try await repo.markPaid(payment.id, at: Self.now)
        _ = await service.synchronize()
        XCTAssertEqual(Array(notifications.pending.keys), ["lolita.outfit.today"])
        XCTAssertTrue(calendar.events.isEmpty)
        let paid = try await repo.getById(payment.id)
        XCTAssertTrue(paid?.isPaid == true)
        XCTAssertEqual(paid?.paidDate, Int64(Self.now.timeIntervalSince1970 * 1000))
    }

    @MainActor
    func testChangingAmountAndDateReplacesExistingReminderWithoutDuplicateCalendarEvents() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        var payment = try await database.dbQueue.write { @Sendable db in try Self.fixture(db) }
        let repo = PaymentRepository(db: database.dbQueue)
        let (defaults, suite, notifications, calendar) = try environment()
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = PaymentReminderService(repository: repo, defaults: defaults, notifications: notifications,
                                            calendar: calendar, now: { Self.now })
        _ = await service.setCalendarEnabled(true)
        payment.amount = 100
        payment.dueDate += 86400 * 1000
        payment.customReminderDays = 2
        try await repo.update(payment)
        _ = await service.synchronize()
        XCTAssertEqual(notifications.pending.count, 1)
        XCTAssertEqual(notifications.additions.count, 2)
        XCTAssertEqual(calendar.events.count, 1)
        XCTAssertEqual(calendar.events.values.first?.amount, 100)
        _ = await service.synchronize()
        XCTAssertEqual(notifications.additions.count, 2)
    }

    @MainActor
    func testDeniedAccessPreservesPaymentAndReportsWarning() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        let payment = try await database.dbQueue.write { @Sendable db in try Self.fixture(db) }
        let repo = PaymentRepository(db: database.dbQueue)
        let (defaults, suite, notifications, calendar) = try environment()
        defer { defaults.removePersistentDomain(forName: suite) }
        notifications.authorized = false
        calendar.access = false
        calendar.grantOnRequest = false
        let service = PaymentReminderService(repository: repo, defaults: defaults, notifications: notifications,
                                            calendar: calendar, now: { Self.now })
        let notificationWarning = await service.requestNotificationAuthorization()
        let calendarWarning = await service.setCalendarEnabled(true)
        XCTAssertNotNil(notificationWarning)
        XCTAssertNotNil(calendarWarning)
        XCTAssertFalse(service.calendarEnabled)
        let result = await service.synchronize()
        XCTAssertNotNil(result.notificationWarning)
        XCTAssertTrue(notifications.additions.isEmpty)
        let stored = try await repo.getById(payment.id)
        XCTAssertEqual(stored?.amount, 123)
        XCTAssertTrue(stored?.reminderSet == true)
    }

    @MainActor
    func testDeliveredCatchupDoesNotRepeatOnForegroundRefresh() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        var payment = try await database.dbQueue.write { @Sendable db in try Self.fixture(db) }
        let repo = PaymentRepository(db: database.dbQueue)
        payment.customReminderDays = 4
        try await repo.update(payment)
        let (defaults, suite, notifications, calendar) = try environment()
        defer { defaults.removePersistentDomain(forName: suite) }
        var current = Self.now
        let service = PaymentReminderService(repository: repo, defaults: defaults, notifications: notifications,
                                            calendar: calendar, now: { current })
        _ = await service.synchronize()
        XCTAssertEqual(notifications.additions.count, 1)
        notifications.pending.removeAll()
        current = current.addingTimeInterval(120)
        _ = await service.synchronize()
        XCTAssertEqual(notifications.additions.count, 1)
        payment.amount = 120
        try await repo.update(payment)
        _ = await service.synchronize()
        XCTAssertEqual(notifications.additions.count, 2)
    }

    @MainActor
    func testObserverSynchronizesPaymentEditsAndCanBeRestarted() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        let payment = try await database.dbQueue.write { @Sendable db in try Self.fixture(db) }
        let repo = PaymentRepository(db: database.dbQueue)
        let (defaults, suite, notifications, calendar) = try environment()
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = PaymentReminderService(repository: repo, defaults: defaults, notifications: notifications,
                                            calendar: calendar, now: { Self.now })
        service.start()
        service.start()
        defer { service.stop() }
        for _ in 0..<100 {
            if notifications.additions.count == 1 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(notifications.additions.count, 1)
        try await repo.markPaid(payment.id, at: Self.now)
        for _ in 0..<100 {
            if notifications.pending.isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(notifications.pending.isEmpty)
        service.stop()
        service.start()
        _ = await service.synchronize()
        XCTAssertTrue(notifications.pending.isEmpty)
    }

    @MainActor
    func testPriceRebuildAndBackupRestoreRemoveOldSystemRegistrations() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        let payment = try await database.dbQueue.write { @Sendable db in try Self.fixture(db) }
        let repo = PaymentRepository(db: database.dbQueue)
        let (defaults, suite, notifications, calendar) = try environment()
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = PaymentReminderService(repository: repo, defaults: defaults, notifications: notifications,
                                            calendar: calendar, now: { Self.now })
        _ = await service.setCalendarEnabled(true)
        let manager = BackupManager(db: database.dbQueue)
        let backup = try await manager.snapshot()
        let prices = PriceRepository(db: database.dbQueue)
        let storedPrice = try await prices.getById(payment.priceId)
        var price = try XCTUnwrap(storedPrice)
        price.totalPrice = 200
        let priorPrice = price
        try await database.dbQueue.write { @Sendable db in
            var current = priorPrice; current.purchaseRecordStatus = .tracked; try current.update(db)
            var stage = PaymentStage(priceId: current.id, name: "全款", amount: 100)
            try stage.insert(db)
            try OrderBinding(itemId: current.itemId, priceId: current.id).insert(db)
        }
        _ = try await prices.saveWithPayments(price)
        _ = await service.synchronize()
        XCTAssertTrue(notifications.pending.isEmpty)
        XCTAssertTrue(calendar.events.isEmpty)
        try await manager.restore(backup)
        _ = await service.synchronize()
        XCTAssertTrue(notifications.pending.isEmpty)
        XCTAssertTrue(calendar.events.isEmpty)
        let restored = try await repo.getById(payment.id)
        XCTAssertNil(restored?.calendarEventId)
        XCTAssertFalse(restored?.reminderSet == true)
    }

    @MainActor
    func testEditorRejectsDeletedRecordAndUsesReminderSubmissionSnapshot() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        let payment = try await database.dbQueue.write { @Sendable db in try Self.fixture(db) }
        let repo = PaymentRepository(db: database.dbQueue)
        let vm = PaymentEditViewModel(priceId: payment.priceId, paymentId: payment.id, repository: repo)
        await vm.load()
        XCTAssertTrue(vm.reminderSet)
        XCTAssertEqual(vm.reminderDaysText, "1")
        vm.reminderDaysText = "-1"
        do { _ = try await vm.save(); XCTFail("负数提前天数必须被拒绝") } catch { }
        XCTAssertFalse(vm.isSaving)
        try await repo.delete(payment)
        vm.reminderDaysText = "1"
        do { _ = try await vm.save(); XCTFail("已删除付款必须报告失败") } catch { }
        XCTAssertFalse(vm.isSaving)
    }
}

@MainActor
private final class FakeNotifications: PaymentNotificationClient {
    var authorized = true
    var pending: [String: PaymentNotificationSnapshot] = [:]
    var additions: [PaymentNotificationPlan] = []
    func isAuthorized() async -> Bool { authorized }
    func requestAuthorization() async throws -> Bool { authorized }
    func pendingRequests() async -> [PaymentNotificationSnapshot] { Array(pending.values) }
    func add(_ plan: PaymentNotificationPlan) async throws {
        additions.append(plan)
        pending[plan.identifier] = PaymentNotificationSnapshot(identifier: plan.identifier, fingerprint: plan.fingerprint)
    }
    func remove(_ identifiers: [String]) { identifiers.forEach { pending.removeValue(forKey: $0) } }
}

@MainActor
private final class FakeCalendar: PaymentCalendarClient {
    var access = true
    var grantOnRequest = true
    var events: [String: PaymentReminderRecord] = [:]
    var hasAccess: Bool { access }
    func requestAccess() async throws -> Bool { access = grantOnRequest; return access }
    func contains(_ identifier: String) -> Bool { events[identifier] != nil }
    func save(_ record: PaymentReminderRecord, existingIdentifier: String?) throws -> String {
        let identifier = existingIdentifier ?? UUID().uuidString
        events[identifier] = record
        return identifier
    }
    func remove(_ identifier: String) throws { events.removeValue(forKey: identifier) }
}
