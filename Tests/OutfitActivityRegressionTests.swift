import XCTest
@testable import lolita

final class OutfitActivityRegressionTests: XCTestCase {
    private func calendar(_ zone: String = "Asia/Shanghai") -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: zone)!
        return value
    }
    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testReminderSkipsRecordedLocalDaysAndPastTime() {
        let cal = calendar()
        let now = date(2026, 10, 11, 21, calendar: cal)
        let tomorrow = date(2026, 10, 12, 12, calendar: cal)
        let records = [OutfitDaySummary(date: tomorrow, itemCount: 0)]
        let values = OutfitReminderPlan.dates(now: now, hour: 20, minute: 15, recorded: records, calendar: cal, days: 4)
        XCTAssertEqual(values.count, 2)
        XCTAssertEqual(cal.component(.day, from: values[0]), 13)
        XCTAssertEqual(cal.component(.minute, from: values[0]), 15)
        XCTAssertTrue(values.allSatisfy { $0 > now })
    }

    func testSavingTodaysRecordSuppressesOnlyToday() {
        let cal = calendar()
        let now = date(2026, 10, 11, 9, calendar: cal)
        let records = [OutfitDaySummary(date: date(2026, 10, 11, 12, calendar: cal), itemCount: 2)]
        let values = OutfitReminderPlan.dates(now: now, hour: 20, minute: 0, recorded: records, calendar: cal)
        XCTAssertEqual(values.count, 13)
        XCTAssertEqual(cal.component(.day, from: values[0]), 12)
        XCTAssertEqual(Set(values.map { OutfitReminderPlan.identifier(for: $0) }).count, 13)
    }

    func testReminderKeepsWallClockAcrossDST() {
        let cal = calendar("America/New_York")
        let values = OutfitReminderPlan.dates(now: date(2026, 3, 7, 9, calendar: cal), hour: 20, minute: 0, recorded: [], calendar: cal, days: 3)
        XCTAssertEqual(values.count, 3)
        XCTAssertEqual(values[1].timeIntervalSince(values[0]), 23 * 3600)
        XCTAssertTrue(values.allSatisfy { cal.component(.hour, from: $0) == 20 })
        XCTAssertTrue(OutfitReminderPlan.dates(now: values[0], hour: 25, minute: 0, recorded: []).isEmpty)
    }

    func testWidgetSnapshotDoesNotCarryYesterdayIntoToday() throws {
        let cal = calendar()
        let yesterday = date(2026, 10, 10, 12, calendar: cal)
        let snapshot = OutfitWidgetSnapshot(days: [OutfitDaySummary(date: yesterday, itemCount: 2)])
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("outfit.json")
        try OutfitWidgetStore.save(snapshot, to: url)
        let restored = try OutfitWidgetStore.load(from: url)
        XCTAssertEqual(restored.record(on: yesterday, calendar: cal)?.itemCount, 2)
        XCTAssertNil(restored.record(on: date(2026, 10, 11, 0, calendar: cal), calendar: cal))
    }

    func testNotificationAndWidgetRoutesRejectInvalidInputs() {
        XCTAssertEqual(AppDeepLink.parse(URL(string: "lolita://today-outfit")!), .todayOutfit)
        XCTAssertEqual(AppDeepLink.parse(URL(string: "lolita://payment/12")!), .payment(12))
        for value in ["https://payment/12", "lolita://payment/-1", "lolita://payment/0", "lolita://payment/1/2", "lolita://today-outfit/extra"] {
            XCTAssertNil(AppDeepLink.parse(URL(string: value)!))
        }
    }
}
