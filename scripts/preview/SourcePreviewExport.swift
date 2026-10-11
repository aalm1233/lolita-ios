#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import lolita

/// Render newly created SwiftUI components, without reading any app window or database.
final class SourcePreviewExport: XCTestCase {
    @MainActor
    func testExport() throws {
        let output = URL(fileURLWithPath: try XCTUnwrap(ProcessInfo.processInfo.environment["LOLITA_PREVIEW_OUTPUT"]))
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for type in SkinType.allCases {
            let widths: [CGFloat] = type == .default ? [320, 393, 430] : [393]
            for width in widths {
                for dark in [false, true] {
                    try export(type: type, width: width, dark: dark, largeText: false, output: output)
                }
            }
        }
        for dark in [false, true] {
            try export(type: .default, width: 320, dark: dark, largeText: true, output: output)
        }
    }

    @MainActor
    private func export(type: SkinType, width: CGFloat, dark: Bool, largeText: Bool, output: URL) throws {
        let skin = SkinManager()
        // Assign this temporary instance only; switching through preferences would alter user settings.
        skin.current = SkinManager.create(type)
        skin.currentSkinType = type
        let boards: [(String, AnyView)] = [
            ("wardrobe", AnyView(WardrobePreviewContent())),
            ("stats", AnyView(StatsPreviewContent())),
            ("editing", AnyView(EditingPreviewContent())),
            ("calendar", AnyView(CalendarPreviewContent())),
            ("themes", AnyView(ThemePreviewContent()))
        ]
        for (name, board) in boards {
            let content = VStack(alignment: .leading, spacing: 16) {
                Text("源码组件预览 · \(Int(width)) pt\(largeText ? " · 辅助字号布局" : "")")
                    .font(.caption).foregroundStyle(.secondary)
                board
            }
            .padding(16)
            .frame(width: width, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .background(dark ? skin.current.backgroundColorDark : skin.current.backgroundColor)
            .environmentObject(skin)
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.dynamicTypeSize, largeText ? .accessibility2 : .large)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.cgImage, "Unable to render \(name)")
            let bitmap = NSBitmapImageRep(cgImage: image)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let filename = "\(name)-\(type.rawValue.lowercased())-\(Int(width))-\(dark ? "dark" : "light")\(largeText ? "-large-text" : "").png"
            try png.write(to: output.appendingPathComponent(filename))
        }
    }
}

@MainActor private enum PreviewItems {
    static let first = Item(id: 1, name: "草莓花园 · 连衣裙", brandId: 1, categoryId: 1, status: .pendingBalance,
                            colors: StringList(["粉色", "白色"]), season: "春夏", style: "甜美", size: "M")
    static let second = Item(id: 2, name: "Alice's Tea Party · 蕾丝蝴蝶结与玫瑰花刺绣长款连衣裙", brandId: 1, categoryId: 1,
                             colors: StringList(["白色"]), style: "经典优雅", size: "均码")
    static let third = Item(id: 3, name: "海风水手 · 发带", brandId: 1, categoryId: 1, style: "水手")
}

private struct WardrobePreviewContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("我的衣橱").font(.title2.weight(.semibold))
            LolitaSegmentedTabs(options: ItemSubTab.allCases, selection: .constant(.items), label: { $0.rawValue })
            LolitaSection(title: "我的服饰") {
                ItemRow(item: PreviewItems.first, brandName: "Angelic Pretty")
                Divider().opacity(0.35)
                ItemRow(item: PreviewItems.second, brandName: "Baby, The Stars Shine Bright")
                Divider().opacity(0.35)
                ItemRow(item: PreviewItems.third)
            }
            LolitaCollectionHeader(title: "共收藏", count: 3)
        }
    }
}

private struct StatsPreviewContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("衣橱统计").font(.title2.weight(.semibold))
            StatsSummaryView(ownedCount: 28, pendingCount: 6, wishedCount: 12, coordinateCount: 8, outfitCount: 32, totalSpending: 27830)
            LolitaSection(title: "品牌 Top 5") {
                StatsRankingRow(rank: 1, name: "Angelic Pretty", count: 12, maximumCount: 12)
                StatsRankingRow(rank: 2, name: "Baby, The Stars Shine Bright", count: 8, maximumCount: 12)
                StatsRankingRow(rank: 3, name: "Innocent World", count: 4, maximumCount: 12)
            }
            StatsDonutCard(title: "品牌消费分布", rows: [StatsChartValue(name: "AP", amount: 12800), StatsChartValue(name: "Baby", amount: 8030), StatsChartValue(name: "其他", amount: 7000)], centerLabel: "总消费", centerValue: "¥27,830")
        }
    }
}

private struct EditingPreviewContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("编辑服饰与套装").font(.title2.weight(.semibold))
            LolitaSection(title: "颜色") {
                EditColorSelection(colors: MatchingEngine.colors, selectedColors: .constant(["粉色", "白色"]))
            }
            LolitaSection(title: "已选服饰 · 2 件") {
                EditSelectedItemRow(item: PreviewItems.first, order: 1, onRemove: {})
                Divider().opacity(0.35)
                EditSelectedItemRow(item: PreviewItems.second, order: 2, onRemove: {})
            }
            LolitaSection(title: "长文字详情") {
                DetailRow(label: "品牌", value: "Baby, The Stars Shine Bright")
                DetailRow(label: "位置", value: "卧室衣柜 · 左侧第二层收纳盒")
            }
            ImageGalleryPager(urls: [])
        }
    }
}

private struct CalendarPreviewContent: View {
    @EnvironmentObject private var skinManager: SkinManager
    @Environment(\.colorScheme) private var colorScheme
    private var accent: Color { colorScheme == .dark ? skinManager.current.primaryColorDark : skinManager.current.primaryColor }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("付款安排").font(.title2.weight(.semibold))
            HStack(spacing: 12) {
                PaymentMonthSummaryCard(month: 10, paymentCount: 4, pendingAmount: 1280, isCurrentMonth: true)
                PaymentMonthSummaryCard(month: 11, paymentCount: 2, pendingAmount: 360)
            }
            LolitaSection(title: "2026 年 10 月") {
                let calendar = Calendar.current
                let firstDay = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
                let firstWeekday = calendar.component(.weekday, from: firstDay)
                let daysInMonth = calendar.range(of: .day, in: .month, for: firstDay)!
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                    ForEach(["日", "一", "二", "三", "四", "五", "六"], id: \.self) { weekday in
                        Text(weekday).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    ForEach(0..<(firstWeekday - 1), id: \.self) { _ in Color.clear.frame(height: 44) }
                    ForEach(daysInMonth, id: \.self) { day in
                        PaymentCalendarDayCell(day: day, hasPayments: [8, 10, 16, 23].contains(day), isSelected: day == 10, isToday: day == 10, accent: accent)
                    }
                }
            }
            LolitaSection(title: "10 月 10 日付款") {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("草莓花园 · 连衣裙").font(.subheadline.weight(.medium))
                        LolitaBadge(text: "待付", color: .orange)
                    }
                    Spacer(minLength: 8)
                    Text("¥680.00").font(.subheadline.weight(.semibold)).monospacedDigit()
                }
            }
        }
    }
}

private struct ThemePreviewContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("主题选择").font(.title2.weight(.semibold))
            SkinPreviewGrid(selectedType: .default)
        }
    }
}
#endif
