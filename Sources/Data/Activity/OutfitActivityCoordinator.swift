import Foundation
import SwiftUI
@preconcurrency import GRDB
#if os(iOS)
@preconcurrency import UserNotifications
import WidgetKit
#endif

@MainActor
final class OutfitActivityCoordinator: ObservableObject {
    static let shared = OutfitActivityCoordinator()
    @Published private(set) var issue: String?
    private var queue: DatabaseQueue?
    private var observationTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?

    func start(db: DatabaseQueue) {
        guard observationTask == nil else { return }
        queue = db
        observationTask = Task { [weak self] in
            for await _ in Self.updates(db: db) {
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    /// Serialize updates, including a change arriving while notification registration awaits.
    func refresh() {
        guard let queue else { return }
        let previous = refreshTask
        previous?.cancel()
        refreshTask = Task { [weak self] in
            await previous?.value
            guard !Task.isCancelled, let self else { return }
            do {
                let records = try await queue.read { @Sendable db in try Self.records(in: db) }
                guard !Task.isCancelled else { return }
                let snapshot = OutfitWidgetSnapshot(days: records)
                #if os(iOS)
                var widgetIssue: String?
                if let url = OutfitWidgetStore.sharedURL {
                    do {
                        try OutfitWidgetStore.save(snapshot, to: url)
                        WidgetCenter.shared.reloadTimelines(ofKind: OutfitWidgetStore.widgetKind)
                    } catch { widgetIssue = "小组件暂时无法更新：" + userFacingError(error) }
                }
                try await synchronizeNotifications(records: records)
                let issues = [issue, widgetIssue].compactMap { $0 }
                issue = issues.isEmpty ? nil : issues.joined(separator: "\n")
                #endif
            } catch {
                if !Task.isCancelled { issue = userFacingError(error) }
            }
        }
    }

    func applyReminder(enabled: Bool, hour: Int, minute: Int) async -> String? {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return "提醒时间无效。" }
        #if os(iOS)
        if enabled {
            do {
                let center = UNUserNotificationCenter.current()
                let settings = await center.notificationSettings()
                if settings.authorizationStatus == .notDetermined {
                    guard try await center.requestAuthorization(options: [.alert, .sound, .badge]) else {
                        return "通知权限未开启，请在系统设置中允许 Lolita 发送通知。"
                    }
                } else if settings.authorizationStatus == .denied {
                    return "通知权限未开启，请在系统设置中允许 Lolita 发送通知。"
                }
            } catch { return userFacingError(error) }
        }
        #endif
        let defaults = UserDefaults.standard
        defaults.set(enabled, forKey: "outfitReminderEnabled")
        defaults.set(hour, forKey: "outfitReminderHour")
        defaults.set(minute, forKey: "outfitReminderMinute")
        #if os(iOS)
        if !enabled {
            refreshTask?.cancel()
            await refreshTask?.value
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests()
            center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("lolita.outfit.") }.map(\.identifier))
        }
        #endif
        issue = nil
        refresh()
        await refreshTask?.value
        return issue
    }

    nonisolated private static func records(in db: Database) throws -> [OutfitDaySummary] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT o.date, COUNT(r.itemId) AS itemCount FROM outfitLogs o
            LEFT JOIN outfitItemCrossRef r ON r.outfitLogId = o.id
            GROUP BY o.id ORDER BY o.date DESC, o.id DESC
            """)
        return rows.map { row in
            OutfitDaySummary(date: Date(timeIntervalSince1970: Double(row["date"] as Int64) / 1000),
                             itemCount: row["itemCount"])
        }
    }

    nonisolated private static func updates(db: DatabaseQueue) -> AsyncStream<[OutfitDaySummary]> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { @Sendable db in try Self.records(in: db) }
            let token = observation.start(in: db, onError: { _ in continuation.finish() },
                                          onChange: { continuation.yield($0) })
            continuation.onTermination = { _ in token.cancel() }
        }
    }

    #if os(iOS)
    private func synchronizeNotifications(records: [OutfitDaySummary]) async throws {
        let center = UNUserNotificationCenter.current()
        let existing = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix("lolita.outfit.") }
        guard !Task.isCancelled else { return }
        let defaults = UserDefaults.standard
        let enabled = defaults.bool(forKey: "outfitReminderEnabled")
        let settings = await center.notificationSettings()
        guard !Task.isCancelled else { return }
        let allowed = [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
        let hour = defaults.object(forKey: "outfitReminderHour") as? Int ?? 20
        let minute = defaults.object(forKey: "outfitReminderMinute") as? Int ?? 0
        let dates = enabled && allowed ? OutfitReminderPlan.dates(now: Date(), hour: hour, minute: minute, recorded: records) : []
        let desired = Set(dates.map { OutfitReminderPlan.identifier(for: $0) })
        center.removePendingNotificationRequests(withIdentifiers: existing.map(\.identifier).filter { !desired.contains($0) })
        let identifiers = Set(existing.map(\.identifier))
        for date in dates where !identifiers.contains(OutfitReminderPlan.identifier(for: date)) {
            guard !Task.isCancelled else { return }
            let content = UNMutableNotificationContent()
            content.title = "今天穿了什么？"
            content.body = "记录一下今天的穿搭吧。"
            content.sound = .default
            content.userInfo = ["url": "lolita://today-outfit"]
            let trigger = UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date), repeats: false)
            try await center.add(UNNotificationRequest(identifier: OutfitReminderPlan.identifier(for: date), content: content, trigger: trigger))
        }
        if records.contains(where: { Calendar.current.isDateInToday($0.date) }) {
            let delivered = await center.deliveredNotifications()
            center.removeDeliveredNotifications(withIdentifiers: delivered.filter { $0.request.identifier.hasPrefix("lolita.outfit.") }.map { $0.request.identifier })
        }
        issue = enabled && !allowed ? "穿搭提醒暂停：请在系统设置中允许通知。" : nil
    }
    #endif
}
