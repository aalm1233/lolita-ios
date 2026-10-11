@preconcurrency import GRDB
@preconcurrency import UserNotifications
@preconcurrency import EventKit
import Combine
import Foundation

struct PaymentReminderRecord: Codable, Sendable, FetchableRecord, Equatable {
    var paymentId: Int64
    var amount: Double
    var dueDate: Int64
    var isPaid: Bool
    var reminderSet: Bool
    var customReminderDays: Int?
    var createdAt: Int64
    var itemName: String
}

struct PaymentNotificationPlan: Sendable, Equatable {
    let identifier: String
    let paymentId: Int64
    let title: String
    let body: String
    let fireDate: Date
    let originalFireDate: Date
    let dueDate: Date
    let fingerprint: String
    var url: String { "lolita://payment/\(paymentId)" }
}

enum PaymentReminderPlanner {
    static let prefix = "lolita.payment."
    static let maximumRequests = 48

    static func reminderDate(due: Date, days: Int, calendar: Calendar = .current) -> Date? {
        calendar.date(byAdding: .day, value: -min(365, max(0, days)), to: due)
    }

    /// Keep calendar-day semantics through daylight saving changes. An earlier reminder
    /// for a payment still due today or later is delivered once after a short delay.
    static func notifications(_ records: [PaymentReminderRecord], now: Date,
                              calendar: Calendar = .current) -> [PaymentNotificationPlan] {
        records.compactMap { record -> PaymentNotificationPlan? in
            guard record.reminderSet, !record.isPaid, record.paymentId > 0,
                  record.amount.isFinite, record.amount >= 0 else { return nil }
            let due = Date(timeIntervalSince1970: Double(record.dueDate) / 1000)
            guard let followingDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: due)),
                  followingDay > now else { return nil }
            let days = min(365, max(0, record.customReminderDays ?? 1))
            guard let original = reminderDate(due: due, days: days, calendar: calendar) else { return nil }
            let fire = original > now ? original : now.addingTimeInterval(60)
            let fingerprint = "\(record.paymentId)|\(record.createdAt)|\(record.dueDate)|\(days)|\(record.amount)|\(record.itemName)|\(calendar.timeZone.identifier)"
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "M月d日"
            return PaymentNotificationPlan(identifier: "\(prefix)\(record.paymentId)", paymentId: record.paymentId,
                title: "付款提醒", body: "\(record.itemName) · ¥\(String(format: "%.2f", record.amount))，\(formatter.string(from: due))到期",
                fireDate: fire, originalFireDate: original, dueDate: due, fingerprint: fingerprint)
        }.sorted {
            if $0.fireDate != $1.fireDate { return $0.fireDate < $1.fireDate }
            if $0.dueDate != $1.dueDate { return $0.dueDate < $1.dueDate }
            return $0.paymentId < $1.paymentId
        }.prefix(maximumRequests).map { $0 }
    }
}

struct PaymentNotificationSnapshot: Sendable {
    var identifier: String
    var fingerprint: String?
}

@MainActor
protocol PaymentNotificationClient {
    func isAuthorized() async -> Bool
    func requestAuthorization() async throws -> Bool
    func pendingRequests() async -> [PaymentNotificationSnapshot]
    func add(_ plan: PaymentNotificationPlan) async throws
    func remove(_ identifiers: [String])
}

@MainActor
protocol PaymentCalendarClient {
    var hasAccess: Bool { get }
    func requestAccess() async throws -> Bool
    func contains(_ identifier: String) -> Bool
    func save(_ record: PaymentReminderRecord, existingIdentifier: String?) throws -> String
    func remove(_ identifier: String) throws
}

@MainActor
private final class SystemPaymentNotificationClient: PaymentNotificationClient {
    private let center = UNUserNotificationCenter.current()
    func isAuthorized() async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        if status == .authorized || status == .provisional { return true }
#if os(iOS)
        return status == .ephemeral
#else
        return false
#endif
    }
    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }
    func pendingRequests() async -> [PaymentNotificationSnapshot] {
        await center.pendingNotificationRequests().map {
            PaymentNotificationSnapshot(identifier: $0.identifier, fingerprint: $0.content.userInfo["fingerprint"] as? String)
        }
    }
    func add(_ plan: PaymentNotificationPlan) async throws {
        let content = UNMutableNotificationContent()
        content.title = plan.title
        content.body = plan.body
        content.sound = .default
        content.userInfo = ["url": plan.url, "fingerprint": plan.fingerprint]
        let interval = max(1, plan.fireDate.timeIntervalSinceNow)
        let request = UNNotificationRequest(identifier: plan.identifier, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false))
        try await center.add(request)
    }
    func remove(_ identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}

@MainActor
private final class SystemPaymentCalendarClient: PaymentCalendarClient {
    private let store = EKEventStore()
    var hasAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }
    func requestAccess() async throws -> Bool { try await store.requestFullAccessToEvents() }
    func contains(_ identifier: String) -> Bool { ownedEvent(identifier) != nil }
    private func ownedEvent(_ identifier: String) -> EKEvent? {
        guard let event = store.event(withIdentifier: identifier),
              event.url?.absoluteString.hasPrefix("lolita://payment/") == true else { return nil }
        return event
    }
    func save(_ record: PaymentReminderRecord, existingIdentifier: String?) throws -> String {
        let event = existingIdentifier.flatMap { ownedEvent($0) } ?? EKEvent(eventStore: store)
        if event.calendar == nil {
            guard let calendar = store.defaultCalendarForNewEvents, calendar.allowsContentModifications else {
                throw ValidationError.invalid("系统日历没有可写入的默认日历，请先在日历应用中添加日历")
            }
            event.calendar = calendar
        }
        event.title = "付款：\(record.itemName) · ¥\(String(format: "%.2f", record.amount))"
        event.startDate = Date(timeIntervalSince1970: Double(record.dueDate) / 1000)
        event.endDate = event.startDate.addingTimeInterval(3600)
        event.timeZone = .current
        event.isAllDay = false
        event.url = URL(string: "lolita://payment/\(record.paymentId)")
        event.notes = "由洛丽塔衣橱同步。付款变更、支付或删除后会同步更新。"
        let days = min(365, max(0, record.customReminderDays ?? 1))
        guard let alarmDate = PaymentReminderPlanner.reminderDate(due: event.startDate, days: days) else {
            throw ValidationError.invalid("无法确定日历提醒日期")
        }
        event.alarms = [EKAlarm(absoluteDate: alarmDate)]
        try store.save(event, span: .thisEvent, commit: true)
        guard let identifier = event.eventIdentifier else { throw ValidationError.invalid("系统日历未返回事件标识") }
        return identifier
    }
    func remove(_ identifier: String) throws {
        guard let event = ownedEvent(identifier) else { return }
        try store.remove(event, span: .thisEvent, commit: true)
    }
}

struct PaymentReminderSyncResult: Sendable {
    var notificationWarning: String?
    var calendarWarning: String?
    var warning: String? {
        let values = [notificationWarning, calendarWarning].compactMap { $0 }
        return values.isEmpty ? nil : values.joined(separator: "\n")
    }
}

@MainActor
final class PaymentReminderService: ObservableObject {
    @Published private(set) var notificationWarning: String?
    @Published private(set) var calendarWarning: String?
    @Published private(set) var calendarEnabled: Bool

    private struct Scheduled: Codable { var fingerprint: String; var fireDate: Date }
    private struct CalendarRegistration: Codable {
        var identifier: String
        var createdAt: Int64
        var record: PaymentReminderRecord
    }
    private let repository: PaymentRepository
    private let notifications: any PaymentNotificationClient
    private let calendar: any PaymentCalendarClient
    private let defaults: UserDefaults
    private let now: () -> Date
    private var observationTask: Task<Void, Never>?
    private var synchronizationTask: Task<PaymentReminderSyncResult, Never>?
    private var synchronizationRequested = false
    private static let calendarEnabledKey = "paymentCalendarEnabled"
    private static let calendarMapKey = "paymentCalendarRegistrations.v1"
    private static let notificationMapKey = "paymentNotificationRegistrations.v1"

    init(repository: PaymentRepository, defaults: UserDefaults = .standard,
         notifications: (any PaymentNotificationClient)? = nil,
         calendar: (any PaymentCalendarClient)? = nil, now: @escaping () -> Date = Date.init) {
        self.repository = repository
        self.defaults = defaults
        self.notifications = notifications ?? SystemPaymentNotificationClient()
        self.calendar = calendar ?? SystemPaymentCalendarClient()
        self.now = now
        self.calendarEnabled = defaults.bool(forKey: Self.calendarEnabledKey)
    }

    /// One observation covers manual payments, price schedules, item cascades and backup restore.
    func start() {
        guard observationTask == nil else { return }
        observationTask = Task { [weak self, repository] in
            for await _ in repository.observeReminderRecords() {
                guard !Task.isCancelled else { return }
                _ = await self?.synchronize()
            }
        }
    }
    func stop() { observationTask?.cancel(); observationTask = nil }

    func requestNotificationAuthorization() async -> String? {
        do {
            guard try await notifications.requestAuthorization() else {
                notificationWarning = "通知权限未开启，付款记录仍可保存；请在系统设置中允许通知后接收提醒"
                return notificationWarning
            }
            notificationWarning = nil
            return nil
        } catch {
            notificationWarning = "暂时无法开启通知，付款记录仍可保存；请稍后在系统设置中检查通知权限"
            return notificationWarning
        }
    }

    func setCalendarEnabled(_ enabled: Bool) async -> String? {
        if enabled && !calendar.hasAccess {
            do {
                guard try await calendar.requestAccess() else {
                    calendarWarning = "日历权限未开启，请在系统设置中允许日历完整访问后重试"
                    return calendarWarning
                }
            } catch {
                calendarWarning = "暂时无法访问系统日历，请在系统设置中检查日历权限后重试"
                return calendarWarning
            }
        }
        calendarEnabled = enabled
        defaults.set(enabled, forKey: Self.calendarEnabledKey)
        let result = await synchronize()
        return result.calendarWarning
    }

    /// Coalesce observer and editor requests without letting an older async snapshot win.
    func synchronize() async -> PaymentReminderSyncResult {
        synchronizationRequested = true
        if let synchronizationTask { return await synchronizationTask.value }
        let task = Task { [weak self] in
            guard let self else { return PaymentReminderSyncResult() }
            var result = PaymentReminderSyncResult()
            while self.synchronizationRequested {
                self.synchronizationRequested = false
                result = await self.performSynchronization()
            }
            self.synchronizationTask = nil
            return result
        }
        synchronizationTask = task
        return await task.value
    }

    private func performSynchronization() async -> PaymentReminderSyncResult {
        let records: [PaymentReminderRecord]
        do { records = try await repository.getReminderRecords() }
        catch {
            notificationWarning = "付款数据暂时无法读取，提醒将在下次打开应用时重试"
            return PaymentReminderSyncResult(notificationWarning: notificationWarning, calendarWarning: calendarWarning)
        }
        await synchronizeNotifications(records)
        synchronizeCalendar(records)
        return PaymentReminderSyncResult(notificationWarning: notificationWarning, calendarWarning: calendarWarning)
    }

    private func synchronizeNotifications(_ records: [PaymentReminderRecord]) async {
        let currentDate = now()
        let plans = PaymentReminderPlanner.notifications(records, now: currentDate)
        let pending = await notifications.pendingRequests()
        let authorized = await notifications.isAuthorized()
        let desired = authorized ? Set(plans.map(\.identifier)) : []
        var history: [String: Scheduled] = read(Self.notificationMapKey) ?? [:]
        let active = Set(plans.map(\.identifier))
        let removed = Set(pending.filter {
            $0.identifier.hasPrefix(PaymentReminderPlanner.prefix) && !desired.contains($0.identifier)
        }.map(\.identifier)).union(history.keys.filter { !active.contains($0) })
        notifications.remove(Array(removed))
        history = history.filter { active.contains($0.key) }
        guard authorized else {
            notificationWarning = plans.isEmpty ? nil : "通知权限未开启，付款已保存；请在系统设置中允许通知后接收提醒"
            write(history, key: Self.notificationMapKey)
            return
        }
        notificationWarning = nil
        let pendingMap = Dictionary(uniqueKeysWithValues: pending.map { ($0.identifier, $0) })
        for plan in plans {
            if pendingMap[plan.identifier]?.fingerprint == plan.fingerprint { continue }
            // A past catch-up reminder has already fired. Foreground refresh must not send it again.
            if pendingMap[plan.identifier] == nil, let old = history[plan.identifier],
               old.fingerprint == plan.fingerprint, old.fireDate <= currentDate { continue }
            do {
                try await notifications.add(plan)
                history[plan.identifier] = Scheduled(fingerprint: plan.fingerprint, fireDate: plan.fireDate)
            } catch { notificationWarning = "付款已保存，但部分通知未能注册；下次打开应用会重试" }
        }
        write(history, key: Self.notificationMapKey)
    }

    private func synchronizeCalendar(_ records: [PaymentReminderRecord]) {
        var registrations: [String: CalendarRegistration] = read(Self.calendarMapKey) ?? [:]
        let eligible = records.filter { $0.reminderSet && !$0.isPaid }
        let desired = calendarEnabled ? Dictionary(uniqueKeysWithValues: eligible.map { (String($0.paymentId), $0) }) : [:]
        guard calendar.hasAccess else {
            calendarWarning = calendarEnabled || !registrations.isEmpty
                ? "日历访问未开启，暂时无法同步或移除付款事件；请在系统设置中允许日历完整访问" : nil
            return
        }
        calendarWarning = nil
        for (paymentId, registration) in registrations {
            guard let record = desired[paymentId], record.createdAt == registration.createdAt else {
                do { try calendar.remove(registration.identifier); registrations.removeValue(forKey: paymentId) }
                catch { calendarWarning = "付款已保存，但部分日历事件未能移除；下次打开应用会重试" }
                continue
            }
        }
        for (paymentId, record) in desired {
            do {
                let existing = registrations[paymentId]
                if let existing, existing.record == record, calendar.contains(existing.identifier) { continue }
                let identifier = try calendar.save(record,
                    existingIdentifier: existing?.createdAt == record.createdAt ? existing?.identifier : nil)
                registrations[paymentId] = CalendarRegistration(identifier: identifier, createdAt: record.createdAt, record: record)
            } catch {
                calendarWarning = error is ValidationError ? userFacingError(error)
                    : "付款已保存，但系统日历同步失败；请检查日历访问权限和默认日历是否可写，下次打开应用会重试"
            }
        }
        write(registrations, key: Self.calendarMapKey)
    }

    private func read<T: Decodable>(_ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    private func write<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
}
