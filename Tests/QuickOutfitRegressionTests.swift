import XCTest
import GRDB
@testable import lolita

final class QuickOutfitRegressionTests: XCTestCase {
    @MainActor
    func testLoadsTodaysSelectionAndUpdatesSameRecordWithoutLosingPhotos() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        let items = try await makeItems(database.dbQueue)
        let calendar = shanghaiCalendar()
        let now = date(2026, 10, 11, hour: 20, calendar: calendar)
        let photo = try imageFile()
        defer { ImageFileHelper.delete(path: photo) }
        let repo = OutfitLogRepository(db: database.dbQueue)
        let log = try await repo.save(
            OutfitLog(date: milliseconds(now), note: "原记录", imageUrls: StringList([photo]), createdAt: 123),
            itemIds: [items[0].id]
        )
        let vm = QuickOutfitLogViewModel(db: database.dbQueue, calendar: calendar, now: { now })

        try await vm.load()
        XCTAssertEqual(vm.existingLogId, log.id)
        XCTAssertEqual(vm.selectedItemIds, [items[0].id])
        XCTAssertEqual(vm.selectedItems.map(\.id), [items[0].id])
        XCTAssertEqual(vm.imageUrls, [photo])
        XCTAssertEqual(vm.note, "原记录")
        XCTAssertFalse(vm.hasChanges)
        vm.note = "尚未保存的备注"
        vm.toggleItem(items[1].id)
        try await vm.load() // A sheet dismissing must not reset the form.
        XCTAssertEqual(vm.note, "尚未保存的备注")
        XCTAssertEqual(vm.selectedItemIds, Set(items.map(\.id)))

        try await vm.save()
        try await vm.save()
        let savedLog = try await repo.getById(log.id)
        let stored = try XCTUnwrap(savedLog)
        let all = try await repo.getAll()
        let linked = try await repo.getItemIds(for: log.id)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(stored.note, "尚未保存的备注")
        XCTAssertEqual(stored.createdAt, 123)
        XCTAssertEqual(stored.imageUrls.values, [photo])
        XCTAssertEqual(Set(linked), Set(items.map(\.id)))
        XCTAssertEqual(calendar.component(.hour, from: Date(timeIntervalSince1970: Double(stored.date) / 1000)), 12)
        XCTAssertFalse(vm.hasChanges)
        vm.discardImages()
        XCTAssertTrue(FileManager.default.fileExists(atPath: photo))
    }

    @MainActor
    func testEmptySelectionCannotSaveAndCancellationCleansOnlyAddedPhotos() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        let items = try await makeItems(database.dbQueue)
        let now = Date()
        let original = try imageFile()
        let added = try imageFile()
        defer { ImageFileHelper.delete(paths: [original, added]) }
        let repo = OutfitLogRepository(db: database.dbQueue)
        let log = try await repo.save(
            OutfitLog(date: milliseconds(now), note: "原记录", imageUrls: StringList([original])),
            itemIds: [items[0].id]
        )
        let vm = QuickOutfitLogViewModel(db: database.dbQueue, now: { now })
        try await vm.load()
        vm.toggleItem(items[0].id)
        vm.note = "保留这段输入"
        vm.imageUrls.append(added)

        do { try await vm.save(); XCTFail("空服饰选择应阻止保存") }
        catch { XCTAssertEqual(error.localizedDescription, "请至少选择一件服饰") }
        XCTAssertFalse(vm.isSaving)
        XCTAssertEqual(vm.note, "保留这段输入")
        XCTAssertEqual(vm.imageUrls, [original, added])
        let stored = try await repo.getById(log.id)
        let linked = try await repo.getItemIds(for: log.id)
        XCTAssertEqual(stored?.note, "原记录")
        XCTAssertEqual(linked, [items[0].id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: added))
        vm.discardImages()
        XCTAssertFalse(FileManager.default.fileExists(atPath: added))
        XCTAssertTrue(FileManager.default.fileExists(atPath: original))
    }

    @MainActor
    func testTwoQuickEditorsLoadedBeforeSaveReuseTodaysNewRecord() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        let items = try await makeItems(database.dbQueue)
        let now = Date()
        let first = QuickOutfitLogViewModel(db: database.dbQueue, now: { now })
        let second = QuickOutfitLogViewModel(db: database.dbQueue, now: { now })
        try await first.load()
        try await second.load()
        XCTAssertNil(first.existingLogId)
        XCTAssertNil(second.existingLogId)
        first.toggleItem(items[0].id)
        second.toggleItem(items[1].id)
        first.note = "第一份输入"
        second.note = "第二份输入"

        try await first.save()
        try await second.save()
        let repo = OutfitLogRepository(db: database.dbQueue)
        let logs = try await repo.getAll()
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(first.existingLogId, second.existingLogId)
        XCTAssertEqual(logs.first?.note, "第二份输入")
        let id = try XCTUnwrap(second.existingLogId)
        let linked = try await repo.getItemIds(for: id)
        XCTAssertEqual(linked, [items[1].id])
    }

    func testLocalDayBoundsIncludeMidnightAndExcludeNextDayAcrossDST() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        // These are respectively 23-hour and 25-hour local days.
        for (month, day, hours) in [(3, 8, 23), (11, 1, 25)] {
            let database = try LolitaDatabase(path: ":memory:")
            let repo = OutfitLogRepository(db: database.dbQueue)
            let start = date(2026, month, day, calendar: calendar)
            let end = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: start))
            XCTAssertEqual(end.timeIntervalSince(start), Double(hours * 3600))
            _ = try await repo.insert(OutfitLog(date: milliseconds(start) - 1, note: "前一天"))
            let midnight = try await repo.insert(OutfitLog(date: milliseconds(start), note: "当天零点"))
            let initial = try await repo.getForDay(containing: start, calendar: calendar)
            XCTAssertEqual(initial?.log.id, midnight.id)
            let last = try await repo.insert(OutfitLog(date: milliseconds(end) - 1, note: "当天最后一毫秒"))
            let next = try await repo.insert(OutfitLog(date: milliseconds(end), note: "次日零点"))
            let currentDay = try await repo.getForDay(containing: start, calendar: calendar)
            let nextDay = try await repo.getForDay(containing: end, calendar: calendar)
            XCTAssertEqual(currentDay?.log.id, last.id)
            XCTAssertEqual(nextDay?.log.id, next.id)
        }
    }

    @MainActor
    func testSavingAfterMidnightUpdatesNewDayWithoutMovingPreviousRecord() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        let items = try await makeItems(database.dbQueue)
        let calendar = shanghaiCalendar()
        let previousDay = date(2026, 10, 11, hour: 23, calendar: calendar)
        let nextDay = date(2026, 10, 12, calendar: calendar)
        var now = previousDay
        let previousPhoto = try imageFile()
        let nextPhoto = try imageFile()
        defer { ImageFileHelper.delete(paths: [previousPhoto, nextPhoto]) }
        let repo = OutfitLogRepository(db: database.dbQueue)
        let previous = try await repo.save(
            OutfitLog(date: milliseconds(previousDay), note: "昨日原记录", imageUrls: StringList([previousPhoto])),
            itemIds: [items[0].id]
        )
        let next = try await repo.save(
            OutfitLog(date: milliseconds(nextDay), note: "次日已有记录", imageUrls: StringList([nextPhoto])),
            itemIds: [items[1].id]
        )
        let vm = QuickOutfitLogViewModel(db: database.dbQueue, calendar: calendar, now: { now })
        try await vm.load()
        XCTAssertEqual(vm.existingLogId, previous.id)
        now = nextDay
        vm.note = "午夜后修改"
        vm.selectedItemIds = [items[1].id]
        vm.removeImage(at: 0)
        try await vm.save()

        let old = try await repo.getById(previous.id)
        let current = try await repo.getById(next.id)
        let logs = try await repo.getAll()
        let oldItems = try await repo.getItemIds(for: previous.id)
        let currentItems = try await repo.getItemIds(for: next.id)
        XCTAssertEqual(logs.count, 2)
        XCTAssertEqual(vm.existingLogId, next.id)
        XCTAssertEqual(old?.date, previous.date)
        XCTAssertEqual(old?.note, "昨日原记录")
        XCTAssertEqual(old?.imageUrls.values, [previousPhoto])
        XCTAssertEqual(oldItems, [items[0].id])
        XCTAssertEqual(current?.note, "午夜后修改")
        XCTAssertEqual(current?.imageUrls.values, [])
        XCTAssertEqual(currentItems, [items[1].id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: previousPhoto))
        XCTAssertFalse(FileManager.default.fileExists(atPath: nextPhoto))
    }

    @MainActor
    func testAssociationFailureRollsBackUpdateAndKeepsInputsUntilDiscard() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        let items = try await makeItems(database.dbQueue)
        let now = Date()
        let original = try imageFile()
        let added = try imageFile()
        defer { ImageFileHelper.delete(paths: [original, added]) }
        let repo = OutfitLogRepository(db: database.dbQueue)
        let log = try await repo.save(
            OutfitLog(date: milliseconds(now), note: "数据库原记录", imageUrls: StringList([original])),
            itemIds: [items[0].id]
        )
        let vm = QuickOutfitLogViewModel(db: database.dbQueue, now: { now })
        try await vm.load()
        vm.note = "失败后保留的输入"
        vm.imageUrls = [added]
        vm.selectedItemIds = [999_999]

        do { try await vm.save(); XCTFail("无效外键应使整个保存事务失败") }
        catch { XCTAssertEqual((error as? DatabaseError)?.extendedResultCode, .SQLITE_CONSTRAINT_FOREIGNKEY) }
        let stored = try await repo.getById(log.id)
        let linked = try await repo.getItemIds(for: log.id)
        XCTAssertEqual(stored?.note, "数据库原记录")
        XCTAssertEqual(stored?.imageUrls.values, [original])
        XCTAssertEqual(stored?.date, log.date)
        XCTAssertEqual(linked, [items[0].id])
        XCTAssertEqual(vm.note, "失败后保留的输入")
        XCTAssertEqual(vm.imageUrls, [added])
        XCTAssertEqual(vm.selectedItemIds, [999_999])
        XCTAssertFalse(vm.isSaving)
        XCTAssertTrue(vm.hasChanges)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original))
        XCTAssertTrue(FileManager.default.fileExists(atPath: added))
        vm.discardImages()
        XCTAssertTrue(FileManager.default.fileExists(atPath: original))
        XCTAssertFalse(FileManager.default.fileExists(atPath: added))
    }

    @MainActor
    func testSavingDefersDiscardAndKeepsSharedOriginalAndCommittedNewPhotos() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        let items = try await makeItems(database.dbQueue)
        let now = Date()
        let shared = try imageFile()
        let added = try imageFile()
        defer { ImageFileHelper.delete(paths: [shared, added]) }
        try await database.dbQueue.write { db in
            var item = items[0]
            item.imageUrls = StringList([shared])
            try item.update(db)
        }
        let repo = OutfitLogRepository(db: database.dbQueue)
        let log = try await repo.save(
            OutfitLog(date: milliseconds(now), note: "", imageUrls: StringList([shared])),
            itemIds: [items[0].id]
        )
        let vm = QuickOutfitLogViewModel(db: database.dbQueue, now: { now })
        try await vm.load()
        vm.removeImage(at: 0)
        vm.imageUrls.append(added)
        let gate = holdDatabase(database.dbQueue)
        defer { gate.release.signal() }
        let saving = Task { try await vm.save() }
        for _ in 0..<100 {
            if vm.isSaving { break }
            await Task.yield()
        }
        XCTAssertTrue(vm.isSaving)
        vm.removeImage(at: 0)
        vm.toggleItem(items[0].id)
        vm.discardImages()
        XCTAssertEqual(vm.imageUrls, [added])
        XCTAssertEqual(vm.selectedItemIds, [items[0].id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: added))
        gate.release.signal()
        try await saving.value
        try await gate.blocker.value

        let stored = try await repo.getById(log.id)
        XCTAssertEqual(stored?.imageUrls.values, [added])
        XCTAssertFalse(vm.isSaving)
        vm.discardImages()
        XCTAssertTrue(FileManager.default.fileExists(atPath: added))
        XCTAssertTrue(FileManager.default.fileExists(atPath: shared), "另一条服饰仍引用的旧图不能清理")
    }

    @MainActor
    private func makeItems(_ queue: DatabaseQueue) async throws -> [Item] {
        try await queue.write { db in
            var brand = Brand(name: UUID().uuidString)
            try brand.insert(db)
            var category = Category(name: UUID().uuidString)
            try category.insert(db)
            var first = Item(name: "连衣裙", brandId: brand.id, categoryId: category.id)
            var second = Item(name: "配饰", brandId: brand.id, categoryId: category.id)
            try first.insert(db)
            try second.insert(db)
            return [first, second]
        }
    }

    private func shanghaiCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func milliseconds(_ date: Date) -> Int64 { Int64(date.timeIntervalSince1970 * 1000) }
    private func imageFile() throws -> String { try XCTUnwrap(ImageFileHelper.save(imageData: Data([1, 2, 3]))) }

    private struct DatabaseGate {
        let release: DispatchSemaphore
        let blocker: Task<Void, Error>
    }

    private func holdDatabase(_ queue: DatabaseQueue) -> DatabaseGate {
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let blocker = Task.detached {
            try await queue.read { _ in
                entered.signal()
                _ = release.wait(timeout: .now() + 10)
            }
        }
        XCTAssertEqual(entered.wait(timeout: .now() + 5), .success)
        return DatabaseGate(release: release, blocker: blocker)
    }
}
