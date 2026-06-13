import SwiftUI

struct StatsPageScreen: View {
    @StateObject private var viewModel = StatsPageViewModel()
    @EnvironmentObject var skinManager: SkinManager

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    StatCard(title: "总服饰", value: "\(viewModel.totalItems)", color: .blue)
                    StatCard(title: "已拥有", value: "\(viewModel.ownedCount)", color: .green)
                    StatCard(title: "愿望单", value: "\(viewModel.wishedCount)", color: .pink)
                    StatCard(title: "穿搭记录", value: "\(viewModel.totalOutfits)", color: .orange)
                }

                if !viewModel.styleDistribution.isEmpty {
                    LolitaSection(title: "风格分布") {
                        ForEach(viewModel.styleDistribution.prefix(10), id: \.0) { style, count in
                            HStack {
                                Text(style)
                                Spacer()
                                Text("\(count)").foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                // Total spending card
                LolitaCard(variant: .compact) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("总消费")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(String(format: "¥%.2f", viewModel.totalSpending))
                                .font(.title2.weight(.bold))
                                .foregroundStyle(skinManager.current.primaryColor)
                        }
                        Spacer()
                    }
                }

                if let exp = viewModel.mostExpensive {
                    LolitaCard(variant: .compact) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("最贵单品")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(exp.itemName)
                                    .font(.subheadline.weight(.medium))
                                Text(String(format: "¥%.2f", exp.totalSpending))
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(skinManager.current.primaryColor)
                            }
                            Spacer()
                        }
                    }
                }

                if !viewModel.spendingByBrand.isEmpty {
                    LolitaSection(title: "品牌消费分布") {
                        ForEach(viewModel.spendingByBrand.prefix(10), id: \.name) { item in
                            HStack {
                                Text(item.name)
                                Spacer()
                                Text(String(format: "¥%.2f", item.totalSpending))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                if !viewModel.spendingByCategory.isEmpty {
                    LolitaSection(title: "品类消费分布") {
                        ForEach(viewModel.spendingByCategory.prefix(10), id: \.name) { item in
                            HStack {
                                Text(item.name)
                                Spacer()
                                Text(String(format: "¥%.2f", item.totalSpending))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                if !viewModel.spendingByStyle.isEmpty {
                    LolitaSection(title: "风格消费分布") {
                        ForEach(viewModel.spendingByStyle.prefix(10), id: \.style) { item in
                            HStack {
                                Text(item.style)
                                Spacer()
                                Text(String(format: "¥%.2f", item.totalSpending))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                if !viewModel.monthlySpending.isEmpty {
                    LolitaSection(title: "月度消费趋势") {
                        ForEach(viewModel.monthlySpending, id: \.yearMonth) { item in
                            HStack {
                                Text(item.yearMonth)
                                Spacer()
                                Text(String(format: "¥%.2f", item.totalSpending))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                // Wishlist Analysis
                LolitaCard(variant: .compact) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("愿望单预算")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(format: "¥%.2f", viewModel.wishlistBudget))
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.pink)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !viewModel.wishlistPriorityStats.isEmpty {
                    LolitaSection(title: "愿望单优先级") {
                        ForEach(viewModel.wishlistPriorityStats, id: \.priority) { stat in
                            HStack {
                                Text(priorityName(stat.priority))
                                Spacer()
                                Text("\(stat.itemCount)件")
                                    .foregroundStyle(.secondary)
                                Text(String(format: "¥%.2f", stat.totalBudget))
                                    .foregroundStyle(.pink)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                // Payment Calendar shortcut
                NavigationLink(destination: PaymentCalendarScreen()) {
                    LolitaCard(variant: .compact) {
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundStyle(skinManager.current.primaryColor)
                            Text("付款日历")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .padding()
        }
        .lolitaNavBar(title: "统计")
        .onAppear { viewModel.load() }
    }

    private func priorityName(_ p: String) -> String {
        switch p {
        case "HIGH": return "高优先"
        case "MEDIUM": return "中优先"
        case "LOW": return "低优先"
        default: return p
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        LolitaCard(variant: .compact) {
            VStack(spacing: 4) {
                Text(value).font(.largeTitle.weight(.bold)).foregroundStyle(color)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
