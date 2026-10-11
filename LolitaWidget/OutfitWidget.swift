import SwiftUI
import WidgetKit

private struct OutfitEntry: TimelineEntry {
    let date: Date
    let record: OutfitDaySummary?
}

private struct OutfitProvider: TimelineProvider {
    func placeholder(in context: Context) -> OutfitEntry { OutfitEntry(date: Date(), record: nil) }
    func getSnapshot(in context: Context, completion: @escaping (OutfitEntry) -> Void) {
        completion(entry(at: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<OutfitEntry>) -> Void) {
        let now = Date()
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86400)
        completion(Timeline(entries: [entry(at: now), entry(at: tomorrow)], policy: .after(tomorrow)))
    }
    private func entry(at date: Date) -> OutfitEntry {
        let snapshot = OutfitWidgetStore.sharedURL.flatMap { try? OutfitWidgetStore.load(from: $0) }
        return OutfitEntry(date: date, record: snapshot?.record(on: date))
    }
}

private struct OutfitWidgetView: View {
    let entry: OutfitEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(entry.date.formatted(.dateTime.month().day().weekday().locale(Locale(identifier: "zh_CN"))), systemImage: "hanger")
                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
            if let record = entry.record {
                Text("今日已记录").font(.headline).foregroundStyle(.pink)
                Text("\(record.itemCount) 件穿搭").font(.subheadline)
                Text("点击查看与编辑").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("今天穿了什么？").font(.headline).foregroundStyle(.pink)
                Text("点击记录今日穿搭").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.background, for: .widget)
        .widgetURL(URL(string: "lolita://today-outfit"))
    }
}

@main
struct LolitaOutfitWidget: Widget {
    let kind = OutfitWidgetStore.widgetKind
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: OutfitProvider()) { OutfitWidgetView(entry: $0) }
            .configurationDisplayName("今日穿搭")
            .description("查看今日记录状态，快速记录或编辑穿搭。")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
