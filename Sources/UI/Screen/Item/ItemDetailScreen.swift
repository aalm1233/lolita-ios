import SwiftUI

struct ItemDetailScreen: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var skinManager: SkinManager
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel: ItemDetailViewModel
    @State private var showDeleteConfirmation = false
    @State private var operationError: String?
    @State private var reloadToken = 0

    init(itemId: Int64) {
        _viewModel = StateObject(wrappedValue: ItemDetailViewModel(itemId: itemId))
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: skinManager.current.spacingL) {
                if let item = viewModel.item {
                    if !viewModel.imageUrls.isEmpty { ImageGalleryPager(urls: viewModel.imageUrls) }
                    DetailTitleCard(title: item.name, subtitle: [viewModel.brandName, viewModel.categoryName].joined(separator: " · ")) {
                        DetailStatusBadge(status: item.status)
                        if item.status == .wished {
                            LolitaBadge(text: "\(detailPriorityName(item.priority))优先级", color: detailAccent(skinManager.current, colorScheme: colorScheme))
                        }
                    }
                    basicInformation(item)
                    if !item.description.isEmpty {
                        LolitaSection(title: "描述") {
                            Text(item.description).font(.body).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if item.size?.isEmpty == false || item.sizeChartImageUrl?.isEmpty == false {
                        LolitaSection(title: "尺码信息") {
                            if let size = item.size, !size.isEmpty { DetailRow(label: "尺码", value: size) }
                            if let path = item.sizeChartImageUrl, !path.isEmpty {
                                ImageGalleryPager(urls: [ImageFileHelper.fileURL(for: path)], emptyTitle: "暂无尺码表")
                                Text("点击尺码表查看原图").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    priceInformation
                    if item.status == .owned {
                        NavigationLink(destination: ItemRecommendationScreen(itemId: item.id)) {
                            LolitaCard {
                                DetailActionLabel(title: "推荐搭配", subtitle: "按服饰分类寻找适合的搭配", systemImage: "sparkles")
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    LolitaSection(title: "记录信息") {
                        DetailRow(label: "创建时间", value: detailDate(item.createdAt))
                        Divider()
                        DetailRow(label: "更新时间", value: detailDate(item.updatedAt))
                    }
                } else {
                    DetailLoadState(isLoading: viewModel.isLoading, message: viewModel.errorMessage ?? "这件服饰已不存在") { reloadToken += 1 }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, skinManager.current.spacingL)
            .padding(.vertical, skinManager.current.spacingL)
        }
        .lolitaNavBar(title: "服饰详情", showBack: true)
        .toolbar {
            #if os(iOS)
            ToolbarItemGroup(placement: .topBarTrailing) { editAndDeleteActions }
            #else
            ToolbarItemGroup(placement: .automatic) { editAndDeleteActions }
            #endif
        }
        .task(id: reloadToken) { await viewModel.load() }
        .alert("删除这件服饰？", isPresented: $showDeleteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                Task {
                    do { try await viewModel.deleteItem(); dismiss() }
                    catch { operationError = userFacingError(error) }
                }
            }
        } message: { Text("这件服饰的价格、付款和关联记录将一并删除。") }
        .alert("操作失败", isPresented: Binding(get: { operationError != nil }, set: { if !$0 { operationError = nil } })) {
            Button("确定") { operationError = nil }
        } message: { Text(operationError ?? "") }
    }

    @ViewBuilder private var editAndDeleteActions: some View {
        if viewModel.item != nil {
            NavigationLink(destination: ItemEditScreen(itemId: viewModel.itemId)) { Image(systemName: "pencil") }
                .accessibilityLabel("编辑服饰")
            Menu {
                Button("删除服饰", systemImage: "trash", role: .destructive) { showDeleteConfirmation = true }
            } label: { Image(systemName: "ellipsis") }
            .accessibilityLabel("更多服饰操作")
        }
    }

    private func basicInformation(_ item: Item) -> some View {
        LolitaSection(title: "基本信息") {
            HStack(spacing: 8) {
                Text("品牌").font(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                LolitaBrandLogo(path: viewModel.brandLogoPath, name: viewModel.brandName, size: 20)
                Text(viewModel.brandName).font(.subheadline.weight(.medium)).multilineTextAlignment(.trailing)
            }.padding(.vertical, 4)
            Divider()
            DetailRow(label: "分类", value: viewModel.categoryName)
            if let coordinate = viewModel.coordinate {
                Divider()
                NavigationLink(destination: CoordinateDetailScreen(coordinateId: coordinate.id)) {
                    DetailDisclosureRow(label: "所属套装", value: coordinate.name)
                }.buttonStyle(.plain)
            }
            if !item.colors.values.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("颜色").font(.subheadline).foregroundStyle(.secondary)
                    DetailFlowLayout(spacing: 6) {
                        ForEach(item.colors.values, id: \.self) { color in
                            LolitaBadge(text: color, color: detailAccent(skinManager.current, colorScheme: colorScheme))
                        }
                    }
                }.padding(.vertical, 3)
            }
            if let style = item.style, !style.isEmpty { Divider(); DetailRow(label: "风格", value: style) }
            if let season = item.season, !season.isEmpty { Divider(); DetailRow(label: "季节", value: season.replacingOccurrences(of: ",", with: "、")) }
            if let source = item.source, !source.isEmpty { Divider(); DetailRow(label: "来源", value: source) }
            Divider()
            NavigationLink(destination: LocationDetailScreen(locationId: item.locationId ?? -1)) {
                DetailDisclosureRow(label: "收纳位置", value: viewModel.locationName)
            }.buttonStyle(.plain)
        }
    }

    private var priceInformation: some View {
        LolitaSection(title: "价格信息") {
            if viewModel.prices.isEmpty {
                Text("暂无价格记录").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 8)
            } else {
                DetailMoneySummary(total: viewModel.totalPrice, paid: viewModel.paidAmount, unpaid: viewModel.unpaidAmount)
                ForEach(viewModel.prices) { summary in
                    NavigationLink(destination: PaymentManageScreen(priceId: summary.id)) {
                        DetailPriceCard(summary: summary)
                    }.buttonStyle(.plain)
                }
            }
            NavigationLink(destination: PriceManageScreen(itemId: viewModel.itemId)) {
                DetailActionLabel(title: "管理价格与付款", systemImage: "yensign.circle")
            }.buttonStyle(.plain)
        }
    }
}

struct ItemRecommendationScreen: View {
    @EnvironmentObject private var skinManager: SkinManager
    @StateObject private var viewModel: ItemDetailViewModel
    @State private var reloadToken = 0

    init(itemId: Int64) { _viewModel = StateObject(wrappedValue: ItemDetailViewModel(itemId: itemId)) }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: skinManager.current.spacingL) {
                if viewModel.isLoading || viewModel.isLoadingRecommendations {
                    DetailLoadState(isLoading: true, message: "正在寻找搭配") {}
                } else if let error = viewModel.errorMessage {
                    DetailLoadState(isLoading: false, message: error) { reloadToken += 1 }
                } else if let item = viewModel.item {
                    LolitaCard(variant: .compact) {
                        HStack(spacing: 12) {
                            LolitaThumbnail(path: item.imageUrls.values.first, symbol: "hanger", width: 56, height: 70)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("为这件服饰搭配").font(.caption).foregroundStyle(.secondary)
                                Text(item.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    if viewModel.recommendationGroups.isEmpty {
                        LolitaEmptyState(title: "暂无推荐搭配", message: "添加更多不同分类的服饰，并完善颜色、风格和季节信息。", systemImage: "sparkles", fillsAvailableSpace: false)
                    } else {
                        ForEach(viewModel.recommendationGroups) { group in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(group.name).font(.headline).padding(.horizontal, 4)
                                ForEach(group.matches, id: \.item.id) { match in
                                    NavigationLink(destination: ItemDetailScreen(itemId: match.item.id)) {
                                        DetailRelatedItemCard(item: match.item, score: match.score)
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(skinManager.current.spacingL)
        }
        .lolitaNavBar(title: "推荐搭配", showBack: true)
        .task(id: reloadToken) {
            await viewModel.load()
            if !Task.isCancelled { await viewModel.loadRecommendations() }
        }
    }
}

struct DetailTitleCard<Badges: View>: View {
    let title: String
    var subtitle = ""
    @ViewBuilder let badges: () -> Badges
    var body: some View {
        LolitaCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                if !subtitle.isEmpty { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
                DetailFlowLayout(spacing: 6) { badges() }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct DetailStatusBadge: View {
    let status: ItemStatus
    var body: some View {
        LolitaBadge(text: status == .wished ? "想要" : status == .pendingBalance ? "待尾款" : "已拥有",
                    color: status == .wished ? .pink : status == .pendingBalance ? .orange : .green)
    }
}

struct DetailRelatedItemCard: View {
    @EnvironmentObject private var skinManager: SkinManager
    @Environment(\.colorScheme) private var colorScheme
    let item: Item
    var brandName = ""
    var categoryName = ""
    var price: Double? = nil
    var score: Double? = nil
    var body: some View {
        LolitaCard(variant: .compact) {
            HStack(spacing: 12) {
                LolitaThumbnail(path: item.imageUrls.values.first, symbol: "hanger", width: 64, height: 80)
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    let labels = [brandName, categoryName].filter { !$0.isEmpty }
                    let metadata = (labels.isEmpty ? [item.style ?? "", item.colors.values.joined(separator: "、")].filter { !$0.isEmpty } : labels).joined(separator: " · ")
                    if !metadata.isEmpty { Text(metadata).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    DetailFlowLayout(spacing: 6) {
                        DetailStatusBadge(status: item.status)
                        if let price { Text(detailMoney(price)).font(.caption.weight(.medium)).foregroundStyle(.secondary).padding(.vertical, 4) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if let score {
                    LolitaBadge(text: "\(Int(score * 100))%", color: detailAccent(skinManager.current, colorScheme: colorScheme))
                } else {
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
        }
    }
}

struct DetailPriceCard: View {
    @EnvironmentObject private var skinManager: SkinManager
    @Environment(\.colorScheme) private var colorScheme
    let summary: DetailPriceSummary
    private var accent: Color { colorScheme == .dark ? skinManager.current.accentColorDark : skinManager.current.accentColor }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(summary.price.type == .full ? "全价" : "定金 + 尾款").font(.subheadline.weight(.medium))
                Spacer(minLength: 8)
                Text(detailMoney(summary.price.totalPrice)).font(.headline).monospacedDigit()
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }.foregroundStyle(accent)
            if summary.price.type == .depositBalance {
                DetailRow(label: "定金", value: detailMoney(summary.price.deposit ?? 0))
                DetailRow(label: "尾款", value: detailMoney(summary.price.balance ?? 0))
            }
            if !summary.payments.isEmpty {
                DetailRow(label: "已付", value: detailMoney(summary.paidAmount))
                DetailRow(label: "待付", value: detailMoney(summary.unpaidAmount))
            }
            if let date = summary.firstPaidDate { Text("首次付款 · \(detailDate(date))").font(.caption).foregroundStyle(.secondary) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: skinManager.current.cornerRadiusS))
    }
}

struct DetailMoneySummary: View {
    @EnvironmentObject private var skinManager: SkinManager
    @Environment(\.colorScheme) private var colorScheme
    let total: Double
    let paid: Double
    let unpaid: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(detailMoney(total)).font(.title2.weight(.semibold)).monospacedDigit()
                .foregroundStyle(colorScheme == .dark ? skinManager.current.primaryColorDark : skinManager.current.primaryColor)
                .lineLimit(1).minimumScaleFactor(0.7)
            DetailFlowLayout(spacing: 12) {
                Text("已付 \(detailMoney(paid))").font(.caption).foregroundStyle(.secondary)
                Text("待付 \(detailMoney(unpaid))").font(.caption).foregroundStyle(unpaid > 0 ? .orange : .secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
    }
}

struct DetailActionLabel: View {
    @EnvironmentObject private var skinManager: SkinManager
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    var subtitle = ""
    let systemImage: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage).font(.title3).foregroundStyle(colorScheme == .dark ? skinManager.current.primaryColorDark : skinManager.current.primaryColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                if !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }.padding(.vertical, 6)
    }
}

struct DetailDisclosureRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack(spacing: 8) {
            DetailRow(label: label, value: value)
            Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
        }.foregroundStyle(.primary)
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(label).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: true, vertical: false)
            Text(value).font(.subheadline).multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .trailing)
        }.padding(.vertical, 3)
    }
}

struct DetailLoadState: View {
    let isLoading: Bool
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            if isLoading { ProgressView() }
            else { Image(systemName: "exclamationmark.circle").font(.title2).foregroundStyle(.secondary) }
            Text(isLoading ? "正在加载" : message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if !isLoading { Button("重新加载", action: retry).buttonStyle(.bordered) }
        }.frame(maxWidth: .infinity).padding(.vertical, 48)
    }
}

struct DetailFlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: proposal.width ?? .infinity).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrange(subviews, width: bounds.width)
        for (index, point) in arrangement.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }
    private func arrange(_ subviews: Subviews, width: CGFloat) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, usedWidth: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            positions.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            usedWidth = max(usedWidth, x - spacing)
        }
        return (CGSize(width: min(width, usedWidth), height: subviews.isEmpty ? 0 : y + rowHeight), positions)
    }
}

func detailMoney(_ value: Double) -> String { String(format: "¥%.2f", value) }
func detailDate(_ timestamp: Int64) -> String {
    Date(timeIntervalSince1970: Double(timestamp) / 1000).formatted(date: .abbreviated, time: .omitted)
}
func detailPriorityName(_ priority: ItemPriority) -> String {
    switch priority { case .high: return "高"; case .medium: return "中"; case .low: return "低" }
}
func detailAccent(_ skin: any SkinProtocol, colorScheme: ColorScheme = .light) -> Color {
    colorScheme == .dark ? skin.accentColorDark : skin.accentColor
}
