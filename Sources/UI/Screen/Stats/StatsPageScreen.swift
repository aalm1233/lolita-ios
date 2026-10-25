import SwiftUI
import Charts

private enum StatsTab: String, CaseIterable {
    case overview = "总览", calendar = "付款年历", distribution = "实付分布", trend = "实付趋势", wishlist = "愿望单"
}

struct StatsPageScreen: View {
    @State private var finance = FinanceSnapshot()
    @StateObject private var viewModel = StatsPageViewModel()
    @EnvironmentObject var skinManager: SkinManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTab: StatsTab = .overview
    @State private var dimension = "品牌"
    @State private var showQuarters = false
    @State private var selectedYear = String(Calendar.current.component(.year, from: Date()))
    @State private var drilldown: StatsItemFilter?
    @AppStorage("showTotalPrice") private var showTotalPrice = true
    @AppStorage("statsDistributionChartStyle") private var distributionStyle: StatsDistributionChartStyle = .donut
    @AppStorage("statsTrendChartStyle") private var trendStyle: StatsTrendChartStyle = .line

    private var primaryColor: Color {
        colorScheme == .dark ? skinManager.current.primaryColorDark : skinManager.current.primaryColor
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                LolitaPageTabs(options: StatsTab.allCases, selection: $selectedTab, label: { $0.rawValue }, compact: true)
                if selectedTab == .calendar {
                    CalendarBackgroundPicker()
                        .frame(width: 44, height: 44)
                }
            }
            .padding(.horizontal, 12)
            .background { SkinTopBarBackground() }

            if selectedTab == .calendar {
                PaymentYearSummaryScreen()
            } else {
                ScrollView {
                    VStack(spacing: skinManager.current.spacingL) {
                        switch selectedTab {
                        case .overview: PurchaseReviewShortcut(); overview
                        case .distribution: distribution
                        case .trend: trend
                        case .wishlist: wishlist
                        case .calendar: EmptyView()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, skinManager.current.spacingL)
                }
            }
        }
        .lolitaNavBar(title: "", isHidden: true)
        .navigationDestination(item: $drilldown) { StatsFilteredItemsScreen(filter: $0) }
        .onAppear { viewModel.load() }
        .task { for await value in AppModule.shared.financeRepository.observe() { finance = value } }
        .onDisappear { viewModel.stopObserving() }
    }

    private var overview: some View {
        Group {
            LolitaSection(title: "资金汇总") {
                FinanceValueRow(title: "全部原实付", amount: finance.totalPaid)
                FinanceValueRow(title: "全部到账退款", amount: finance.totalRefunded)
                FinanceValueRow(title: "全部净支出", amount: finance.totalNet)
                NavigationLink("月预算与年度付款", destination: FinanceOverviewScreen())
                Text("分布与趋势按原实付展示；月预算按真实付款与退款到账日期计算净支出。").font(.caption).foregroundStyle(.secondary)
            }
            StatsSummaryView(
                ownedCount: viewModel.ownedCount,
                pendingCount: viewModel.pendingCount,
                wishedCount: viewModel.wishedCount,
                coordinateCount: viewModel.totalCoordinates,
                outfitCount: viewModel.totalOutfits,
                totalSpending: viewModel.totalSpending,
                onSelectStatus: { drilldown = .status($0) },
                pendingPaymentCount: viewModel.pendingPaymentCount,
                pendingReviewCount: viewModel.pendingReviewCount
            )
            NavigationLink { CoordinateListScreen() } label: {
                HStack {
                    SkinLabel("查看全部套装", systemImage: "square.stack")
                    Spacer()
                    Text("\(viewModel.totalCoordinates) 套").foregroundStyle(.secondary)
                    SkinIcon(systemName: "chevron.right", size: 12)
                }.font(.subheadline).padding(12)
            }.buttonStyle(.plain)

            if let item = viewModel.mostExpensive {
                LolitaSection(title: "最贵单品") {
                    NavigationLink(destination: ItemDetailScreen(itemId: item.itemId)) {
                        HStack(spacing: skinManager.current.spacingM) {
                            Text(item.itemName)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Spacer(minLength: 8)
                            Text(statsMoney(item.totalSpending, visible: showTotalPrice))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(primaryColor)
                            SkinIcon(systemName: "chevron.right", size: 12)
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
                        filterLink(.attribute("品牌", row.0, ownedOnly: true)) {
                            StatsRankingRow(rank: index + 1, name: row.0, count: row.1, maximumCount: rows.map(\.1).max() ?? 1)
                        }
                    }
                }
            }

            LolitaSection(title: "风格分布") {
                if viewModel.styleDistribution.isEmpty {
                    StatsEmptyState(title: "暂无风格记录", subtitle: "为服饰选择风格，查看衣橱的搭配偏好。", systemImage: "sparkles")
                } else {
                    ForEach(viewModel.styleDistribution, id: \.0) { name, count in
                        filterLink(.attribute("风格", name, ownedOnly: false)) {
                            StatsRankingRow(name: name, count: count, maximumCount: viewModel.styleDistribution.map(\.1).max() ?? 1)
                        }
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
            LolitaSegmentedTabs(options: StatsDistributionChartStyle.allCases, selection: $distributionStyle, label: { $0.rawValue })
            if buckets.isEmpty {
                LolitaCard {
                    StatsEmptyState(title: "暂无消费记录", subtitle: "记录付款后，在这里查看消费分布。")
                }
            } else {
                let chartRows = dimension == "月份" ? buckets : StatsAggregates.groupedDistribution(buckets)
                StatsDonutCard(title: "\(dimension)消费分布", rows: chartRows, centerLabel: "合计",
                    centerValue: statsMoney(buckets.reduce(0) { $0 + $1.amount }, visible: showTotalPrice),
                    style: distributionStyle, onSelect: { name in
                        guard let row = chartRows.first(where: { $0.name == name }) else { return }
                        drilldown = distributionFilter(row)
                    })
                if dimension == "季节" {
                    Text("多季节服饰会分别计入所选季节，累计金额包含重复归类。")
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }
                LolitaSection(title: "\(dimension)消费明细") {
                    ForEach(Array(chartRows.enumerated()), id: \.element.id) { index, row in
                        filterLink(distributionFilter(row)) {
                            StatsAmountRow(name: row.name, amount: row.amount,
                                color: statsChartColor(index: index, skin: skinManager.current, isDark: colorScheme == .dark),
                                percentage: buckets.reduce(0) { $0 + $1.amount } > 0 ? row.amount / buckets.reduce(0) { $0 + $1.amount } : 0)
                        }
                    }
                }
            }
        }
    }

    private func distributionFilter(_ row: StatsChartValue) -> StatsItemFilter {
        if dimension == "月份" { return .paymentPeriod(row.name) }
        if !row.members.isEmpty { return .attributes(dimension, row.members, ownedOnly: true) }
        return .attribute(dimension, row.name, ownedOnly: true)
    }

    private var trend: some View {
        let rows = viewModel.trendSpending(year: selectedYear, quarters: showQuarters)
        return Group {
            HStack {
                Text("消费年份").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Picker("消费年份", selection: $selectedYear) {
                    Text("全部年份").tag("全部年份")
                    ForEach(viewModel.spendingYears, id: \.self) { Text("\($0) 年").tag($0) }
                }.labelsHidden()
            }
            LolitaSegmentedTabs(options: [false, true], selection: $showQuarters, label: { $0 ? "按季度" : "按月份" })
            LolitaSegmentedTabs(options: StatsTrendChartStyle.allCases, selection: $trendStyle, label: { $0.rawValue })
            HStack {
                Text(selectedYear == "全部年份" ? "历史已付合计" : "\(selectedYear) 年已付合计").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text(statsMoney(rows.reduce(0) { $0 + $1.totalSpending }, visible: showTotalPrice)).font(.headline).foregroundStyle(primaryColor).monospacedDigit()
            }.padding(.vertical, 6)
            if rows.isEmpty {
                LolitaCard {
                    StatsEmptyState(title: "暂无已付记录", subtitle: "完成付款后，可以查看消费随时间的变化。", systemImage: "chart.xyaxis.line")
                }
            } else {
                StatsTrendCard(title: showQuarters ? "季度消费趋势" : "月度消费趋势",
                    rows: rows.map { StatsChartValue(name: $0.yearMonth, amount: $0.totalSpending) }, style: trendStyle,
                    onSelect: { drilldown = .paymentPeriod($0) })
                LolitaSection(title: showQuarters ? "季度消费" : "月度消费") {
                    ForEach(rows, id: \.yearMonth) { row in
                        filterLink(.paymentPeriod(row.yearMonth)) {
                            StatsAmountRow(name: row.yearMonth, amount: row.totalSpending)
                        }
                    }
                }
            }
        }
    }

    private var wishlist: some View {
        Group {
            LolitaCard(variant: .compact) {
                HStack(spacing: 12) {
                    SkinLabel("愿望单预算", systemImage: "heart")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text(statsMoney(viewModel.wishlistBudget, visible: showTotalPrice))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(primaryColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .layoutPriority(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            LolitaCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("已实现 (\(viewModel.ownedCount)/\(viewModel.ownedCount + viewModel.wishedCount))")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(viewModel.wishlistFulfillmentRate, format: .percent.precision(.fractionLength(1)))
                            .font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(primaryColor)
                    }
                    ProgressView(value: viewModel.wishlistFulfillmentRate).tint(primaryColor)
                    Text("已拥有件数 ÷（已拥有 + 心愿），待尾款不计入实现率。")
                        .font(.caption).foregroundStyle(.secondary)
                }
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
                    centerValue: "\(viewModel.wishlistPriorityStats.reduce(0) { $0 + $1.itemCount })",
                    valuesAreMoney: false, onSelect: { name in
                        guard let priority = viewModel.wishlistPriorityStats.first(where: { priorityName($0.priority) == name }) else { return }
                        drilldown = .priority(ItemPriority(rawValue: priority.priority) ?? .medium)
                    }
                )
                LolitaSection(title: "优先级明细") {
                    ForEach(Array(viewModel.wishlistPriorityStats.enumerated()), id: \.element.priority) { index, row in
                        filterLink(.priority(ItemPriority(rawValue: row.priority) ?? .medium)) { HStack(spacing: skinManager.current.spacingM) {
                            Circle()
                                .fill(statsChartColor(index: index, skin: skinManager.current, isDark: colorScheme == .dark))
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(priorityName(row.priority)).font(.subheadline.weight(.medium))
                                Text("\(row.itemCount) 件心愿").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Text(statsMoney(row.totalBudget, visible: showTotalPrice))
                                .font(.subheadline.weight(.medium))
                                .monospacedDigit()
                        }
                        .padding(.vertical, skinManager.current.spacingS)
                        }
                    }
                }
            }
        }
    }

    private func filterLink<Content: View>(_ filter: StatsItemFilter, @ViewBuilder content: () -> Content) -> some View {
        Button { drilldown = filter } label: {
            HStack(spacing: 10) {
                content().frame(maxWidth: .infinity, alignment: .leading)
                SkinIcon(systemName: "chevron.right", size: 12).foregroundStyle(.tertiary)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
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
    @AppStorage("showTotalPrice") private var showTotalPrice = true
    @EnvironmentObject var skinManager: SkinManager
    @Environment(\.colorScheme) private var colorScheme
    let ownedCount: Int
    let pendingCount: Int
    let wishedCount: Int
    let coordinateCount: Int
    let outfitCount: Int
    let totalSpending: Double
    var onSelectStatus: ((ItemStatus) -> Void)? = nil
    var pendingPaymentCount = 0
    var pendingReviewCount = 0

    private var primaryColor: Color {
        colorScheme == .dark ? skinManager.current.primaryColorDark : skinManager.current.primaryColor
    }

    var body: some View {
        VStack(spacing: skinManager.current.spacingM + skinManager.current.spacingS) {
            LolitaCard(variant: .compact) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        SkinLabel("已录实付", systemImage: "yensign.circle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        SkinLabel("\(outfitCount) 次穿搭", systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Text(statsMoney(totalSpending, visible: showTotalPrice))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(primaryColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .layoutPriority(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: skinManager.current.spacingM + skinManager.current.spacingS) {
                statusCard(.owned, title: "已拥有", count: ownedCount, icon: "hanger")
                statusCard(.pendingBalance, title: "待尾款", count: pendingCount, icon: "clock")
                if pendingPaymentCount > 0 { statusCard(.pendingPayment, title: "待付款", count: pendingPaymentCount, icon: "creditcard") }
                if pendingReviewCount > 0 { statusCard(.pendingReview, title: "待核对", count: pendingReviewCount, icon: "questionmark.circle") }
                statusCard(.wished, title: "心愿", count: wishedCount, icon: "heart")
                StatCard(title: "套装", value: "\(coordinateCount)", color: primaryColor, systemImage: "square.stack")
            }
        }
    }

    @ViewBuilder private func statusCard(_ status: ItemStatus, title: String, count: Int, icon: String) -> some View {
        if let onSelectStatus {
            Button { onSelectStatus(status) } label: {
                StatCard(title: title, value: "\(count)", color: primaryColor, systemImage: icon)
            }.buttonStyle(.plain)
        } else {
            StatCard(title: title, value: "\(count)", color: primaryColor, systemImage: icon)
        }
    }
}

struct StatsFilteredItemsScreen: View {
    @AppStorage("showTotalPrice") private var showTotalPrice = true
    let filter: StatsItemFilter
    @StateObject private var viewModel = StatsPageViewModel()
    @State private var search = ""

    private var items: [Item] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return viewModel.filteredItems(filter).filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                LolitaCollectionHeader(title: "筛选结果", count: items.count)
                if items.isEmpty {
                    LolitaEmptyState(title: search.isEmpty ? "暂无符合条件的服饰" : "未找到相关服饰", message: "更换条件后再试试。", systemImage: "magnifyingglass")
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)], spacing: 12) {
                        ForEach(items, id: \.id) { item in
                            NavigationLink { ItemDetailScreen(itemId: item.id) } label: {
                                ItemCollectionCard(item: item, brandName: viewModel.brands.first { $0.id == item.brandId }?.name,
                                                   brandLogoPath: viewModel.brands.first { $0.id == item.brandId }?.logoUrl,
                                                   categoryName: viewModel.categories.first { $0.id == item.categoryId }?.name,
                                                   price: showTotalPrice ? viewModel.pricesByItem[item.id] : nil)
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }.padding(16)
        }
        .searchable(text: $search, prompt: "搜索服饰")
        .lolitaNavBar(title: filter.title, showBack: true)
        .onAppear { viewModel.load() }
        .onDisappear { viewModel.stopObserving() }
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
                    SkinIcon(systemName: systemImage, size: 12)
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
    @AppStorage("showTotalPrice") private var showTotalPrice = true
    @EnvironmentObject var skinManager: SkinManager
    let name: String
    let amount: Double
    var color: Color? = nil
    var percentage: Double? = nil

    var body: some View {
        HStack(spacing: skinManager.current.spacingM) {
            if let color {
                Circle().fill(color).frame(width: 8, height: 8)
            }
            Text(name).font(.subheadline).lineLimit(2)
            Spacer(minLength: 8)
            Text(statsMoney(amount, visible: showTotalPrice))
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let percentage {
                Text(percentage, format: .percent.precision(.fractionLength(1)))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .padding(.vertical, skinManager.current.spacingS)
    }
}

struct StatsDonutCard: View {
    @EnvironmentObject var skinManager: SkinManager
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("showTotalPrice") private var showTotalPrice = true
    let title: String
    let rows: [StatsChartValue]
    let centerLabel: String
    let centerValue: String
    var style: StatsDistributionChartStyle = .donut
    var valuesAreMoney = true
    var onSelect: ((String) -> Void)? = nil

    private var positiveRows: [StatsChartValue] { rows.filter { $0.amount.isFinite && $0.amount > 0 } }
    private var displayedCenter: String { valuesAreMoney && !showTotalPrice ? "¥***" : centerValue }
    private var total: Double { positiveRows.reduce(0) { $0 + $1.amount } }

    var body: some View {
        LolitaCard {
            VStack(alignment: .leading, spacing: skinManager.current.spacingL) {
                Text(title).font(.subheadline.weight(.semibold))
                if positiveRows.isEmpty {
                    VStack(spacing: skinManager.current.spacingM) {
                        SkinIcon(systemName: "chart.pie", size: 22).foregroundStyle(.tertiary)
                        Text(valuesAreMoney ? "暂无金额数据" : "暂无件数数据")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, skinManager.current.spacingXL)
                } else {
                    Chart(positiveRows) { row in
                        if style == .bar {
                            BarMark(x: .value(valuesAreMoney && !showTotalPrice ? "占比%" : "数值", plottedAmount(row.amount)), y: .value("维度", row.name))
                                .foregroundStyle(by: .value("维度", row.name))
                                .cornerRadius(3)
                                .accessibilityLabel(row.name)
                                .accessibilityValue(accessibleValue(row))
                        } else {
                            SectorMark(angle: .value(valuesAreMoney && !showTotalPrice ? "占比%" : "数值", plottedAmount(row.amount)), innerRadius: .ratio(style == .donut ? 0.72 : 0), angularInset: 2)
                                .cornerRadius(3)
                                .foregroundStyle(by: .value("维度", row.name))
                                .accessibilityLabel(row.name)
                                .accessibilityValue(accessibleValue(row))
                        }
                    }
                    .chartForegroundStyleScale(domain: rows.map(\.name), range: rows.indices.map { statsChartColor(index: $0, skin: skinManager.current, isDark: colorScheme == .dark) })
                    .chartLegend(.hidden)
                    .chartXAxis {
                        if style == .bar {
                            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                                AxisGridLine()
                                if !valuesAreMoney || showTotalPrice { AxisValueLabel().font(.caption2) }
                            }
                        }
                    }
                    .chartYAxis {
                        if style == .bar { AxisMarks(position: .leading) { AxisValueLabel().font(.caption2) } }
                    }
                    .chartBackground { proxy in
                        GeometryReader { geometry in
                            if style == .donut, let plotFrame = proxy.plotFrame {
                                let frame = geometry[plotFrame]
                                VStack(spacing: 4) {
                                    Text(centerLabel).font(.caption).foregroundStyle(.secondary)
                                    Text(displayedCenter).font(.title3.weight(.semibold)).monospacedDigit()
                                        .lineLimit(1).minimumScaleFactor(0.6)
                                }
                                .frame(width: min(frame.width, frame.height) * 0.64, height: frame.height)
                                .position(x: frame.midX, y: frame.midY)
                            }
                        }
                    }
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            Color.clear.contentShape(Rectangle()).gesture(SpatialTapGesture().onEnded { tap in
                                guard onSelect != nil, let plotFrame = proxy.plotFrame else { return }
                                let frame = geometry[plotFrame]
                                guard frame.contains(tap.location) else { return }
                                if style == .bar {
                                    let y = tap.location.y - frame.minY
                                    let name = positiveRows.compactMap { row -> (String, CGFloat)? in
                                        proxy.position(forY: row.name).map { (row.name, abs($0 - y)) }
                                    }.min { $0.1 < $1.1 }?.0
                                    if let name { onSelect?(name) }
                                } else {
                                    let dx = tap.location.x - frame.midX
                                    let dy = tap.location.y - frame.midY
                                    let radius = hypot(dx, dy)
                                    let outerRadius = min(frame.width, frame.height) / 2
                                    guard radius <= outerRadius, style != .donut || radius >= outerRadius * 0.72 else { return }
                                    var angle = atan2(dx, -dy)
                                    if angle < 0 { angle += 2 * .pi }
                                    if let name = StatsChartSelection.sector(at: angle / (2 * .pi), rows: positiveRows) { onSelect?(name) }
                                }
                            })
                        }
                    }
                    .frame(height: style == .bar ? max(210, CGFloat(positiveRows.count) * 30) : 210)
                    .accessibilityLabel("\(title)，\(centerLabel)\(displayedCenter)")
                    if onSelect != nil {
                        Text(style == .bar ? "点击柱状条查看服饰明细" : "点击图表切片查看服饰明细")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func accessibleValue(_ row: StatsChartValue) -> String {
        let value = valuesAreMoney ? statsMoney(row.amount, visible: showTotalPrice) : String(format: "%.0f 件", row.amount)
        return "\(value)，\(String(format: "%.1f%%", row.amount / total * 100))"
    }
    private func plottedAmount(_ amount: Double) -> Double {
        StatsDisplay.chartAmount(amount, total: total, visible: !valuesAreMoney || showTotalPrice)
    }
}

struct StatsTrendCard: View {
    @EnvironmentObject var skinManager: SkinManager
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("showTotalPrice") private var showTotalPrice = true
    let title: String
    let rows: [StatsChartValue]
    var style: StatsTrendChartStyle = .line
    var onSelect: ((String) -> Void)? = nil
    private var total: Double { rows.reduce(0) { $0 + $1.amount } }
    private func plottedAmount(_ amount: Double) -> Double { StatsDisplay.chartAmount(amount, total: total, visible: showTotalPrice) }

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
                    if style == .bar {
                        BarMark(x: .value("时间", row.name), y: .value(showTotalPrice ? "金额" : "占比%", plottedAmount(row.amount)))
                            .foregroundStyle(primaryColor).cornerRadius(3)
                            .accessibilityLabel(row.name).accessibilityValue(statsMoney(row.amount, visible: showTotalPrice))
                    } else {
                        AreaMark(x: .value("时间", row.name), y: .value(showTotalPrice ? "金额" : "占比%", plottedAmount(row.amount)))
                            .foregroundStyle(LinearGradient(colors: [primaryColor.opacity(0.20), primaryColor.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                            .accessibilityHidden(true)
                        LineMark(x: .value("时间", row.name), y: .value(showTotalPrice ? "金额" : "占比%", plottedAmount(row.amount)))
                            .foregroundStyle(primaryColor).lineStyle(StrokeStyle(lineWidth: 2))
                            .accessibilityHidden(true)
                        PointMark(x: .value("时间", row.name), y: .value(showTotalPrice ? "金额" : "占比%", plottedAmount(row.amount)))
                            .foregroundStyle(primaryColor).symbolSize(24)
                            .accessibilityLabel(row.name).accessibilityValue(statsMoney(row.amount, visible: showTotalPrice))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: axisLabels) { value in
                        AxisValueLabel {
                            if let label = value.as(String.self) { Text(label.count == 7 ? String(label.suffix(5)) : label).font(.caption2) }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine().foregroundStyle(primaryColor.opacity(0.10))
                        if showTotalPrice { AxisValueLabel().font(.caption2) }
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Color.clear.contentShape(Rectangle()).gesture(SpatialTapGesture().onEnded { tap in
                            guard onSelect != nil, let plotFrame = proxy.plotFrame else { return }
                            let frame = geometry[plotFrame]
                            guard frame.contains(tap.location) else { return }
                            let x = tap.location.x - frame.minX
                            let name = rows.compactMap { row -> (String, CGFloat)? in
                                proxy.position(forX: row.name).map { (row.name, abs($0 - x)) }
                            }.min { $0.1 < $1.1 }?.0
                            if let name { onSelect?(name) }
                        })
                    }
                }
                .frame(height: 220)
                if onSelect != nil { Text("点击图表查看对应期间已付服饰").font(.caption).foregroundStyle(.secondary) }
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
            SkinIcon(systemName: systemImage, size: 22)
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
                NavigationLink("年度退款、净支出与预算", destination: FinanceOverviewScreen(month: date(month: 1), annual: true))
                HStack {
                    Button { year -= 1 } label: {
                        SkinIcon(systemName: "chevron.left").frame(width: 40, height: 40)
                    }
                    .accessibilityLabel("上一年")
                    Spacer()
                    Text("\(String(year)) 年").font(.title3.weight(.semibold)).monospacedDigit()
                    Spacer()
                    Button { year += 1 } label: {
                        SkinIcon(systemName: "chevron.right").frame(width: 40, height: 40)
                    }
                    .accessibilityLabel("下一年")
                }
                .buttonStyle(.plain)

                LolitaSection(title: "全年付款") {
                    StatsAmountRow(name: "已付", amount: payments.filter(\.isPaid).reduce(0) { $0 + $1.amount }, color: .green)
                    StatsAmountRow(name: "待付", amount: payments.filter { !$0.isPaid }.reduce(0) { $0 + $1.amount }, color: .orange)
                    StatsAmountRow(name: "逾期", amount: payments.filter { !$0.isPaid && $0.dueDate < Int64(Date().timeIntervalSince1970 * 1000) }.reduce(0) { $0 + $1.amount }, color: .red)
                }

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
            .padding(.horizontal, skinManager.current.spacingL)
            .padding(.top, 8)
            .padding(.bottom, skinManager.current.spacingL)
        }
        .background { CalendarBackground() }
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
    @AppStorage("showTotalPrice") private var showTotalPrice = true
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
                    Text(statsMoney(pendingAmount, visible: showTotalPrice))
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
        .accessibilityLabel("\(month) 月，\(paymentCount) 笔付款，待付\(statsMoney(pendingAmount, visible: showTotalPrice))")
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
            SkinIcon(systemName: "chevron.right", size: 10)
                .foregroundStyle(.tertiary)
        }
    }
}

private func statsMoney(_ amount: Double, visible: Bool) -> String {
    StatsDisplay.money(amount, visible: visible)
}

private func statsChartColor(index: Int, skin: any SkinProtocol, isDark: Bool) -> Color {
    let primary = isDark ? skin.primaryColorDark : skin.primaryColor
    let accent = isDark ? skin.accentColorDark : skin.accentColor
    let secondary = isDark ? skin.secondaryColorDark : skin.secondaryColor
    let palette = [primary, secondary, accent.opacity(0.68), primary.opacity(0.45), secondary.opacity(0.65)]
    return palette[index % palette.count]
}
