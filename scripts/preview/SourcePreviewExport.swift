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
            ("order-ledger", AnyView(OrderLedgerPreviewContent())),
            ("wardrobe", AnyView(WardrobePreviewContent())),
            ("home-search", AnyView(HomeSearchPreviewContent())),
            ("outfits", AnyView(OutfitListPreviewContent())),
            ("gallery", AnyView(GalleryPreviewContent())),
            ("personal", AnyView(PersonalPreviewContent())),
            ("detail", AnyView(DetailPreviewContent())),
            ("stats", AnyView(StatsPreviewContent())),
            ("editing", AnyView(EditingPreviewContent())),
            ("calendar", AnyView(CalendarPreviewContent())),
            ("themes", AnyView(ThemePreviewContent()))
        ]
        for (name, board) in boards {
            if let scene = ProcessInfo.processInfo.environment["LOLITA_PREVIEW_SCENE"], scene != name { continue }
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
            // Native text fields and menus are represented by their labels in ImageRenderer.
            LolitaHomeToolbar(isSearching: false, onSearch: {}, onCancel: {}) {
                LolitaPageTabs(options: ItemSubTab.allCases, selection: .constant(.items), label: { $0.rawValue }, compact: true)
            } actions: {
                ForEach(["line.3.horizontal.decrease.circle", "arrow.up.arrow.down", "square.grid.2x2"], id: \.self) { symbol in
                    Image(systemName: symbol).frame(width: 36, height: 44)
                }
            } searchField: {
                Text("搜索服饰").foregroundStyle(.secondary).lineLimit(1)
            }
            HStack {
                Text("3 件服饰").font(.subheadline.weight(.semibold))
                Spacer()
                Text("合计 ¥2,380").font(.caption.weight(.semibold)).foregroundStyle(.pink)
            }
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)], spacing: 12) {
                ItemCollectionCard(item: PreviewItems.first, brandName: "Angelic Pretty", categoryName: "连衣裙", price: 1280)
                ItemCollectionCard(item: PreviewItems.second, brandName: "Baby, The Stars Shine Bright", categoryName: "连衣裙", price: 980)
                ItemCollectionCard(item: PreviewItems.third, brandName: "Innocent World", categoryName: "发带", price: 120)
            }
            Text("套装与穿搭").font(.headline)
            CoordinateCollectionCard(coordinate: Coordinate(name: "草莓茶会", description: "春日出游的搭配"), items: [PreviewItems.first, PreviewItems.third], price: 1400, mode: .list)
            OutfitLogCollectionCard(log: OutfitLog(date: 1_791_670_400_000, note: "今天穿着草莓花园和朋友去看展。"), items: [PreviewItems.first, PreviewItems.third])
        }
    }
}

private struct HomeSearchPreviewContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LolitaHomeToolbar(isSearching: true, onSearch: {}, onCancel: {}, clearSearch: {}) {
                EmptyView()
            } actions: {
                EmptyView()
            } searchField: {
                Text("草莓").foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("搜索结果").font(.caption).foregroundStyle(.secondary)
            ItemCollectionCard(item: PreviewItems.first, brandName: "Angelic Pretty", categoryName: "连衣裙", price: 1280)
        }
    }
}

private struct OutfitListPreviewContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LolitaRootToolbar(title: "穿搭日记", subtitle: "3 篇 · 3 天") {
                ForEach(["magnifyingglass", "sun.max", "plus"], id: \.self) { symbol in
                    Image(systemName: symbol).frame(width: 44, height: 44)
                }
            }
            Text("2026 年 10 月 11 日").font(.caption).foregroundStyle(.secondary)
            OutfitLogCollectionCard(log: OutfitLog(date: 1_791_670_400_000, note: "今天穿着草莓花园和朋友去看展。"),
                                    items: [PreviewItems.first, PreviewItems.third])
            OutfitLogCollectionCard(log: OutfitLog(date: 1_791_584_000_000, note: "秋天的茶会，试试新的蕾丝裙。"),
                                    items: [PreviewItems.second])
        }
    }
}

private struct GalleryPreviewContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("服饰画廊").font(.title2.weight(.semibold))
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)], spacing: 12) {
                ItemCollectionCard(item: PreviewItems.first, brandName: "Angelic Pretty", categoryName: "连衣裙", price: 1280, mode: .gallery)
                ItemCollectionCard(item: PreviewItems.second, brandName: "Baby, The Stars Shine Bright", categoryName: "连衣裙", price: 980, mode: .gallery)
            }
            Text("信息列表").font(.headline)
            ItemCollectionCard(item: PreviewItems.first, brandName: "Angelic Pretty", categoryName: "连衣裙", price: 1280, mode: .list)
            ItemCollectionCard(item: PreviewItems.second, brandName: "Baby, The Stars Shine Bright", categoryName: "连衣裙", price: 980, mode: .list)
        }
    }
}

private struct PersonalPreviewContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LolitaRootToolbar(title: "个人") { EmptyView() }
            PersonalProfileCard(nickname: "草莓茶会", avatarPath: "", itemCount: 139, coordinateCount: 27, totalSpent: 27830, onEditNickname: {}) {
                PersonalAvatarView(path: "", color: .pink)
            }
            SettingsMenuCard(title: "属性管理", subtitle: "品牌、分类、风格、季节、位置与渠道", symbol: "square.grid.2x2", color: .purple)
            SettingsMenuCard(title: "数据备份与恢复", subtitle: "ZIP 图片备份、安卓备份恢复与全表 CSV", symbol: "externaldrive", color: .blue)
            SettingsMenuCard(title: "淘宝订单导入", subtitle: "选择订单 Excel，核对定金尾款后导入", symbol: "cart", color: .orange)
            SettingsMenuCard(title: "提醒与系统日历", subtitle: "付款通知、日历联动和每日穿搭提醒", symbol: "bell", color: .teal)
            SettingsMenuCard(title: "皮肤选择", subtitle: "默认 · 粉白", symbol: "paintpalette", color: .pink)
            LolitaSection(title: "显示设置") {
                HStack { Text("显示总价"); Spacer(); Image(systemName: "checkmark.circle.fill").foregroundStyle(.pink) }
            }
        }
    }
}

private struct DetailPreviewContent: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("服饰详情").font(.title2.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
            LolitaCollectionImage(path: nil, title: "草莓花园", symbol: "tshirt", ratio: 0.9)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            DetailTitleCard(title: PreviewItems.first.name, subtitle: "Angelic Pretty · 连衣裙") {
                LolitaBadge(text: "待尾款", color: .orange)
            }
            LolitaSection(title: "基本信息") {
                DetailRow(label: "品牌", value: "Angelic Pretty")
                DetailRow(label: "风格", value: "甜系")
                DetailRow(label: "季节", value: "春,秋")
                DetailRow(label: "所属套装", value: "草莓茶会")
            }
            LolitaSection(title: "价格与付款") {
                StatsAmountRow(name: "总价", amount: 1280)
                StatsAmountRow(name: "已付", amount: 300, color: .green)
                StatsAmountRow(name: "待付", amount: 980, color: .orange)
            }
        }
    }
}

private struct StatsPreviewContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LolitaPageTabs(options: ["总览", "付款年历", "消费分布", "消费趋势", "愿望单"], selection: .constant("总览"), label: { $0 }, compact: true)
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
                EditColorSelection(colors: MatchingEngine.colors, selectedColors: .constant(["粉色", "白色", "香槟金"]))
            }
            LolitaSection(title: "季节") { EditSeasonSelection(seasons: MatchingEngine.seasons, selection: .constant("春,秋")) }
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

private struct OrderLedgerPreviewContent: View {
    private var order: OrderSnapshot {
        OrderSnapshot(price: Price(id: 1, itemId: 1, type: .multiStage, totalPrice: 1234.56, shipping: 12, purchaseRecordStatus: .tracked),
            binding: OrderBinding(itemId: 1, priceId: 1),
            stages: [PaymentStage(id: 1, priceId: 1, name: "定金", amount: 200), PaymentStage(id: 2, priceId: 1, name: "尾款", amount: 1034.56)],
            payments: [Payment(id: 1, priceId: 1, amount: 120, dueDate: 1000, isPaid: true, paidDate: 1000)])
    }
    var body: some View {
        VStack(spacing: 16) {
            Text("订单与账本").font(.headline)
            OrderLedgerSummary(order: order)
            OrderLedgerSummary(order: order, showAmount: false)
            LolitaSection(title: "历史购买资料待核对") {
                Text("原账本、照片和付款日期全部保留，确认历史已购不会补造实付。")
                    .font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
#endif
