import SwiftUI
import Charts

private enum StatsTab: String, CaseIterable {
    case overview = "总览", calendar = "年历", distribution = "分布", trend = "趋势", wishlist = "心愿"
}

struct StatsChartValue: Identifiable {
    let name: String
    let amount: Double
    var id: String { name }
}

struct StatsPageScreen: View {
    @StateObject private var viewModel = StatsPageViewModel()
    @EnvironmentObject var skinManager: SkinManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTab: StatsTab = .overview
    @State private var dimension = "品牌"
    @State private var showQuarters = false

    private var primaryColor: Color {
        colorScheme == .dark ? skinManager.current.primaryColorDark : skinManager.current.primaryColor
    }

    var body: some View {
        VStack(spacing: 0) {
            LolitaSegmentedTabs(options: StatsTab.allCases, selection: $selectedTab, label: { $0.rawValue })
                .padding(.horizontal, skinManager.current.spacingL)
                .padding(.vertical, skinManager.current.spacingM)

            if selectedTab == .calendar {
                PaymentYearSummaryScreen()
            } else {
                ScrollView {
                    VStack(spacing: skinManager.current.spacingL) {
                        switch selectedTab {
                        case .overview: overview
                        case .distribution: distribution
                        case .trend: trend
                        case .wishlist: wishlist
                        case .calendar: EmptyView()
                        }
                    }
                    .padding(.horizontal, selectedTab == .overview ? skinManager.current.spacingM : skinManager.current.spacingL)
                    .padding(.vertical, skinManager.current.spacingL)
                }
            }
        }
        .lolitaNavBar(title: "统计")
        .onAppear { viewModel.load() }
        .onDisappear { viewModel.stopObserving() }
    }

    private var overview: some View {
        Group {
            StatsSummaryView(
                ownedCount: viewModel.ownedCount,
                pendingCount: viewModel.pendingCount,
                wishedCount: viewModel.wishedCount,
                coordinateCount: viewModel.totalCoordinates,
                outfitCount: viewModel.totalOutfits,
                totalSpending: viewModel.totalSpending
            )

            if let item = viewModel.mostExpensive {
                LolitaSection(title: "最贵单品") {
                    NavigationLink(destination: ItemDetailScreen(itemId: item.itemId)) {
                        HStack(spacing: skinManager.current.spacingM) {
                            Text(item.itemName)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Spacer(minLength: 8)
                            Text(statsMoney(item.totalSpending))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(primaryColor)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, skinManager.current.spacingS)
                    }
                    .buttonStyle(.plain)
                }
            }

            LolitaSection(title: "品牌 Top 5") {
                if viewModel.topBrands.isEmpty {
                    StatsEmptyState(title: "暂无品牌记录", subtitle: "添加服饰后，可以查看品牌排行。", systemImage: "tag")
                } else {
                    let rows = Array(viewModel.topBrands.prefix(5))
                    ForEach(Array(rows.enumerated()), id: \.element.0) { index, row in
                        StatsRankingRow(rank: index + 1, name: row.0, count: row.1, maximumCount: rows.map(\.1).max() ?? 1)
                    }
                }
            }

            LolitaSection(title: "风格分布") {
                if viewModel.styleDistribution.isEmpty {
                    StatsEmptyState(title: "暂无风格记录", subtitle: "为服饰选择风格，查看衣橱的搭配偏好。", systemImage: "sparkles")
                } else {
                    ForEach(viewModel.styleDistribution, id: \.0) { name, count in
                        StatsRankingRow(name: name, count: count, maximumCount: viewModel.styleDistribution.map(\.1).max() ?? 1)
                    }
                }
            }
        }
    }

    private var buckets: [StatsChartValue] {
        switch dimension {
        case "分类": return viewModel.spendingByCategory.map { StatsChartValue(name: $0.name, amount: $0.totalSpending) }
        case "风格": return viewModel.spendingByStyle.map { StatsChartValue(name: $0.style, amount: $0.totalSpending) }
        case "季节": return viewModel.spendingBySeason.map { StatsChartValue(name: $0.style, amount: $0.totalSpending) }
        case "月份": return viewModel.monthlySpending.map { StatsChartValue(name: $0.yearMonth, amount: $0.totalSpending) }
        default: return viewModel.spendingByBrand.map { StatsChartValue(name: $0.name, amount: $0.totalSpending) }
        }
    }

    private var distribution: some View {
        Group {
            LolitaSegmentedTabs(options: ["品牌", "分类", "风格", "季节", "月份"], selection: $dimension, label: { $0 })
            if buckets.isEmpty {
                LolitaCard {
                    StatsEmptyState(title: "暂无消费记录", subtitle: "记录付款后，在这里查看消费分布。")
                }
            } else {
                StatsDonutCard(title: "\(dimension)消费分布", rows: buckets, centerLabel: "合计", centerValue: statsMoney(buckets.reduce(0) { $0 + $1.amount }))
                LolitaSection(title: "\(dimension)消费明细") {
                    ForEach(Array(buckets.enumerated()), id: \.element.id) { index, row in
                        StatsAmountRow(name: row.name, amount: row.amount, color: statsChartColor(index: index, skin: skinManager.current, isDark: colorScheme == .dark))
                    }
                }
            }
        }
    }

    private var trend: some View {
        let rows = showQuarters ? viewModel.quarterlySpending : viewModel.monthlySpending
        return Group {
            LolitaSegmentedTabs(options: [false, true], selection: $showQuarters, label: { $0 ? "按季度" : "按月份" })
            if rows.isEmpty {
                LolitaCard {
                    StatsEmptyState(title: "暂无已付记录", subtitle: "完成付款后，可以查看消费随时间的变化。", systemImage: "chart.xyaxis.line")
                }
            } else {
                StatsTrendCard(title: showQuarters ? "季度消费趋势" : "月度消费趋势", rows: rows.map { StatsChartValue(name: $0.yearMonth, amount: $0.totalSpending) })
                LolitaSection(title: showQuarters ? "季度消费" : "月度消费") {
                    ForEach(rows, id: \.yearMonth) { row in
                        StatsAmountRow(name: row.yearMonth, amount: row.totalSpending)
                    }
                }
            }
        }
    }

    private var wishlist: some View {
        Group {
            LolitaCard(variant: .featured) {
                VStack(alignment: .leading, spacing: skinManager.current.spacingM) {
                    Label("愿望单预算", systemImage: "heart")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(statsMoney(viewModel.wishlistBudget))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(primaryColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if viewModel.wishlistPriorityStats.isEmpty {
                LolitaCard {
                    StatsEmptyState(title: "愿望单还是空的", subtitle: "收藏心仪的服饰后，可以比较优先级与预算。", systemImage: "heart")
                }
            } else {
                StatsDonutCard(
                    title: "心愿优先级",
                    rows: viewModel.wishlistPriorityStats.map { StatsChartValue(name: priorityName($0.priority), amount: Double($0.itemCount)) },
                    centerLabel: "心愿件数",
                    centerValue: "\(viewModel.wishlistPriorityStats.reduce(0) { $0 + $1.itemCount })"
                )
                LolitaSection(title: "优先级明细") {
                    ForEach(Array(viewModel.wishlistPriorityStats.enumerated()), id: \.element.priority) { index, row in
                        HStack(spacing: skinManager.current.spacingM) {
                            Circle()
                                .fill(statsChartColor(index: index, skin: skinManager.current, isDark: colorScheme == .dark))
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(priorityName(row.priority)).font(.subheadline.weight(.medium))
                                Text("\(row.itemCount) 件心愿").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Text(statsMoney(row.totalBudget))
                                .font(.subheadline.weight(.medium))
                                .monospacedDigit()
                        }
                        .padding(.vertical, skinManager.current.spacingS)
                    }
                }
            }
        }
    }

    private func priorityName(_ value: String) -> String {
        switch value {
        case "HIGH": return "高优先"
        case "LOW": return "低优先"
        default: return "中优先"
        }
    }
}

struct StatsSummaryView: View {
    @EnvironmentObject var skinManager: SkinManager
    @Environment(\.colorScheme) private var colorScheme
    let ownedCount: Int
    let pendingCount: Int
    let wishedCount: Int
    let coordinateCount: Int
    let outfitCount: Int
    let totalSpending: Double

    private var primaryColor: Color {
        colorScheme == .dark ? skinManager.current.primaryColorDark : skinManager.current.primaryColor
    }

    var body: some View {
        VStack(spacing: skinManager.current.spacingM + skinManager.current.spacingS) {
            LolitaCard(variant: .featured) {
                VStack(alignment: .leading, spacing: skinManager.current.spacingM) {
                    HStack {
                        Label("总消费", systemImage: "yensign.circle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Label("\(outfitCount) 次穿搭", systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(statsMoney(totalSpending))
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(primaryColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: skinManager.current.spacingM + skinManager.current.spacingS) {
                StatCard(title: "已拥有", value: "\(ownedCount)", color: primaryColor, systemImage: "hanger")
                StatCard(title: "待尾款", value: "\(pendingCount)", color: primaryColor, systemImage: "clock")
                StatCard(title: "心愿", value: "\(wishedCount)", color: primaryColor, systemImage: "heart")
                StatCard(title: "套装", value: "\(coordinateCount)", color: primaryColor, systemImage: "square.stack")
            }
        }
    }
}

struct StatCard: View {
    @EnvironmentObject var skinManager: SkinManager
    let title: String
    let value: String
    let color: Color
    var systemImage: String = "square.grid.2x2"

    var body: some View {
        LolitaCard(variant: .compact) {
            VStack(alignment: .leading, spacing: skinManager.current.spacingM) {
                HStack(spacing: 6) {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(color)
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(value)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, skinManager.current.spacingM)
        }
        .accessibilityElement(children: .combine)
    }
}

struct StatsRankingRow: View {
    @EnvironmentObject var skinManager: SkinManager
    @Environment(\.colorScheme) private var colorScheme
    var rank: Int? = nil
    let name: String
    let count: Int
    let maximumCount: Int

    private var accentColor: Color {
        colorScheme == .dark ? skinManager.current.accentColorDark : skinManager.current.accentColor
    }

    var body: some View {
        HStack(spacing: skinManager.current.spacingM) {
            if let rank {
                Text(String(rank))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(rank == 1 ? accentColor : .secondary)
                    .frame(width: 24, height: 24)
                    .background(accentColor.opacity(rank == 1 ? 0.12 : 0.05), in: RoundedRectangle(cornerRadius: skinManager.current.cornerRadiusS))
            }
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(name)
                        .font(.subheadline)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Text("\(count) 件")
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                GeometryReader { geometry in
                    Capsule().fill(accentColor.opacity(0.10))
                    Capsule().fill(accentColor.opacity(rank == 1 ? 0.95 : 0.65))
                        .frame(width: geometry.size.width * min(1, max(0, Double(count) / Double(max(1, maximumCount)))))
                }
                .frame(height: 5)
            }
        }
        .padding(.vertical, skinManager.current.spacingS)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rank.map { "第\($0)名，" } ?? "")\(name)，\(count) 件")
    }
}

struct StatsAmountRow: View {
    @EnvironmentObject var skinManager: SkinManager
    let name: String
    let amount: Double
    var color: Color? = nil

    var body: some View {
        HStack(spacing: skinManager.current.spacingM) {
            if let color {
                Circle().fill(color).frame(width: 8, height: 8)
            }
            Text(name).font(.subheadline).lineLimit(2)
            Spacer(minLength: 8)
            Text(statsMoney(amount))
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, skinManager.current.spacingS)
    }
}

struct StatsDonutCard: View {
    @EnvironmentObject var skinManager: SkinManager
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let rows: [StatsChartValue]
    let centerLabel: String
    let centerValue: String

    private var positiveRows: [StatsChartValue] {
        rows.filter { $0.amount > 0 }
    }

    var body: some View {
        LolitaCard {
            VStack(alignment: .leading, spacing: skinManager.current.spacingL) {
                Text(title).font(.subheadline.weight(.semibold))
                if positiveRows.isEmpty {
                    VStack(spacing: skinManager.current.spacingM) {
                        Image(systemName: "chart.pie")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                        Text("暂无金额数据")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, skinManager.current.spacingXL)
                } else {
                    Chart(positiveRows) { row in
                        SectorMark(angle: .value("数值", row.amount), innerRadius: .ratio(0.72), angularInset: 2)
                            .cornerRadius(3)
                            .foregroundStyle(by: .value("维度", row.name))
                    }
                    .chartForegroundStyleScale(domain: rows.map(\.name), range: rows.indices.map { statsChartColor(index: $0, skin: skinManager.current, isDark: colorScheme == .dark) })
                    .chartLegend(.hidden)
                    .chartBackground { proxy in
                        GeometryReader { geometry in
                            if let plotFrame = proxy.plotFrame {
                                let frame = geometry[plotFrame]
                                VStack(spacing: 4) {
                                    Text(centerLabel).font(.caption).foregroundStyle(.secondary)
                                    Text(centerValue)
                                        .font(.title3.weight(.semibold))
                                        .monospacedDigit()
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.6)
                                }
                                .frame(width: min(frame.width, frame.height) * 0.64, height: frame.height)
                                .position(x: frame.midX, y: frame.midY)
                            }
                        }
                    }
                    .frame(height: 210)
                    .accessibilityLabel("\(title)，\(centerLabel)\(centerValue)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct StatsTrendCard: View {
    @EnvironmentObject var skinManager: SkinManager
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let rows: [StatsChartValue]

    private var primaryColor: Color {
        colorScheme == .dark ? skinManager.current.primaryColorDark : skinManager.current.primaryColor
    }

    private var axisLabels: [String] {
        guard rows.count > 6 else { return rows.map(\.name) }
        let step = max(1, Int(ceil(Double(rows.count - 1) / 5)))
        var labels = stride(from: 0, to: rows.count, by: step).map { rows[$0].name }
        if labels.last != rows.last?.name, let last = rows.last?.name { labels.append(last) }
        return labels
    }

    var body: some View {
        LolitaCard {
            VStack(alignment: .leading, spacing: skinManager.current.spacingL) {
                Text(title).font(.subheadline.weight(.semibold))
                Chart(rows) { row in
                    AreaMark(x: .value("时间", row.name), y: .value("金额", row.amount))
                        .foregroundStyle(LinearGradient(colors: [primaryColor.opacity(0.20), primaryColor.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("时间", row.name), y: .value("金额", row.amount))
                        .foregroundStyle(primaryColor)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    PointMark(x: .value("时间", row.name), y: .value("金额", row.amount))
                        .foregroundStyle(primaryColor)
                        .symbolSize(24)
                }
                .chartXAxis {
                    AxisMarks(values: axisLabels) { value in
                        AxisValueLabel {
                            if let label = value.as(String.self) {
                                Text(label.count == 7 ? String(label.suffix(5)) : label).font(.caption2)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine().foregroundStyle(primaryColor.opacity(0.10))
                        AxisValueLabel().font(.caption2)
                    }
                }
                .frame(height: 220)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct StatsEmptyState: View {
    @EnvironmentObject var skinManager: SkinManager
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let subtitle: String
    var systemImage: String = "chart.bar.xaxis"

    var body: some View {
        VStack(spacing: skinManager.current.spacingM) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(colorScheme == .dark ? skinManager.current.primaryColorDark : skinManager.current.primaryColor)
                .padding(.bottom, skinManager.current.spacingS)
            Text(title).font(.subheadline.weight(.medium))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, skinManager.current.spacingL)
    }
}

struct PaymentYearSummaryScreen: View {
    @EnvironmentObject var skinManager: SkinManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var payments: [PaymentWithItemInfo] = []

    private var monthColumns: [GridItem] {
        Array(repeating: GridItem(.flexible()), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: skinManager.current.spacingL) {
                HStack {
                    Button { year -= 1 } label: {
                        Image(systemName: "chevron.left").frame(width: 40, height: 40)
                    }
                    .accessibilityLabel("上一年")
                    Spacer()
                    Text("\(String(year)) 年").font(.title3.weight(.semibold)).monospacedDigit()
                    Spacer()
                    Button { year += 1 } label: {
                        Image(systemName: "chevron.right").frame(width: 40, height: 40)
                    }
                    .accessibilityLabel("下一年")
                }
                .buttonStyle(.plain)

                LazyVGrid(columns: monthColumns, spacing: skinManager.current.spacingM + skinManager.current.spacingS) {
                    ForEach(1...12, id: \.self) { month in
                        let values = payments.filter { Calendar.current.component(.month, from: Date(timeIntervalSince1970: Double($0.dueDate) / 1000)) == month }
                        NavigationLink(destination: PaymentCalendarScreen(month: date(month: month))) {
                            PaymentMonthSummaryCard(
                                month: month,
                                paymentCount: values.count,
                                pendingAmount: values.filter { !$0.isPaid }.reduce(0) { $0 + $1.amount },
                                isCurrentMonth: Calendar.current.component(.year, from: Date()) == year && Calendar.current.component(.month, from: Date()) == month
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(skinManager.current.spacingL)
        }
        .task(id: year) {
            payments = []
            let start = Int64(date(month: 1).timeIntervalSince1970 * 1000)
            let end = Int64(Calendar.current.date(byAdding: .year, value: 1, to: date(month: 1))!.timeIntervalSince1970 * 1000)
            for await values in AppModule.shared.paymentRepository.getByDateRange(start: start, end: end) {
                guard !Task.isCancelled else { return }
                payments = values
            }
        }
    }

    private func date(month: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: 1))!
    }
}

struct PaymentMonthSummaryCard: View {
    @EnvironmentObject var skinManager: SkinManager
    @Environment(\.colorScheme) private var colorScheme
    let month: Int
    let paymentCount: Int
    let pendingAmount: Double
    var isCurrentMonth: Bool = false

    private var primaryColor: Color {
        colorScheme == .dark ? skinManager.current.primaryColorDark : skinManager.current.primaryColor
    }

    var body: some View {
        LolitaCard {
            VStack(alignment: .leading, spacing: skinManager.current.spacingM) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: skinManager.current.spacingM) {
                        monthTitle
                        Spacer(minLength: 4)
                        monthIndicator
                    }
                    VStack(alignment: .leading, spacing: skinManager.current.spacingS) {
                        monthTitle
                        monthIndicator
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("待付").font(.caption2).foregroundStyle(.secondary)
                    Text(statsMoney(pendingAmount))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(pendingAmount > 0 ? primaryColor : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Text("\(paymentCount) 笔付款")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(month) 月，\(paymentCount) 笔付款，待付\(statsMoney(pendingAmount))")
    }

    private var monthTitle: some View {
        Text("\(month) 月")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isCurrentMonth ? primaryColor : .primary)
            .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder private var monthIndicator: some View {
        if isCurrentMonth {
            Text("本月")
                .font(.caption2.weight(.medium))
                .foregroundStyle(primaryColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(primaryColor.opacity(0.12), in: Capsule())
                .fixedSize(horizontal: true, vertical: false)
        } else {
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
    }
}

private func statsMoney(_ amount: Double) -> String {
    String(format: "¥%.2f", amount)
}

private func statsChartColor(index: Int, skin: any SkinProtocol, isDark: Bool) -> Color {
    let primary = isDark ? skin.primaryColorDark : skin.primaryColor
    let accent = isDark ? skin.accentColorDark : skin.accentColor
    let secondary = isDark ? skin.secondaryColorDark : skin.secondaryColor
    let palette = [primary, secondary, accent.opacity(0.68), primary.opacity(0.45), secondary.opacity(0.65)]
    return palette[index % palette.count]
}
