import Foundation

struct OutfitDaySummary: Codable, Equatable, Sendable {
    let date: Date
    let itemCount: Int
}

struct OutfitWidgetSnapshot: Codable, Equatable, Sendable {
    let days: [OutfitDaySummary]

    func record(on date: Date, calendar: Calendar = .current) -> OutfitDaySummary? {
        days.first { calendar.isDate($0.date, inSameDayAs: date) }
    }
}

enum OutfitWidgetStore {
    static let groupIdentifier = "group.com.lolita.ios"
    static let widgetKind = "LolitaOutfitWidget"

    static var sharedURL: URL? {
        #if os(iOS)
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)?
            .appendingPathComponent("outfit-widget.json")
        #else
        nil
        #endif
    }

    static func save(_ snapshot: OutfitWidgetSnapshot, to url: URL) throws {
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url, options: .atomic)
    }

    static func load(from url: URL) throws -> OutfitWidgetSnapshot {
        try JSONDecoder().decode(OutfitWidgetSnapshot.self, from: Data(contentsOf: url))
    }
}

enum OutfitReminderPlan {
    /// Exact dates allow a saved record to cancel only that day's reminder.
    static func dates(now: Date, hour: Int, minute: Int, recorded: [OutfitDaySummary],
                      calendar: Calendar = .current, days: Int = 14) -> [Date] {
        guard (0...23).contains(hour), (0...59).contains(minute), days > 0 else { return [] }
        let start = calendar.startOfDay(for: now)
        return (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start),
                  !recorded.contains(where: { calendar.isDate($0.date, inSameDayAs: day) }),
                  let fire = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                  fire > now else { return nil }
            return fire
        }
    }

    static func identifier(for date: Date) -> String {
        "lolita.outfit.\(Int64(date.timeIntervalSince1970))"
    }
}
