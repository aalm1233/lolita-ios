import SwiftUI

struct ItemDetailScreen: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var skinManager: SkinManager
    @StateObject private var viewModel: ItemDetailViewModel

    init(itemId: Int64) {
        _viewModel = StateObject(wrappedValue: ItemDetailViewModel(itemId: itemId))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: skinManager.current.cardGap) {
                ImageGalleryPager(urls: viewModel.imageUrls)

                LolitaCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(viewModel.item?.name ?? "")
                            .font(.title2.weight(.bold))

                        if let item = viewModel.item {
                            HStack(spacing: 8) {
                                LolitaBadge(text: item.status == .wished ? "想要" : item.status == .pendingBalance ? "待尾款" : "已拥有",
                                            color: item.status == .wished ? .pink : item.status == .pendingBalance ? .orange : .green)
                            }
                        }

                        if let desc = viewModel.item?.description, !desc.isEmpty {
                            Text(desc)
                                .font(.body)
                                .foregroundStyle(.secondary)
                            Divider()
                        }

                        if !viewModel.brandName.isEmpty {
                            DetailRow(label: "品牌", value: viewModel.brandName)
                        }
                        if !viewModel.categoryName.isEmpty {
                            DetailRow(label: "分类", value: viewModel.categoryName)
                        }
                        if let style = viewModel.item?.style, !style.isEmpty {
                            DetailRow(label: "风格", value: style)
                        }
                        if let season = viewModel.item?.season, !season.isEmpty {
                            DetailRow(label: "季节", value: season)
                        }
                        if let size = viewModel.item?.size, !size.isEmpty {
                            DetailRow(label: "尺码", value: size)
                        }
                        if !viewModel.locationName.isEmpty {
                            DetailRow(label: "位置", value: viewModel.locationName)
                        }
                        if let item = viewModel.item, !item.colors.values.isEmpty {
                            DetailRow(label: "颜色", value: item.colors.values.joined(separator: "、"))
                        }
                        if let source = viewModel.item?.source, !source.isEmpty {
                            DetailRow(label: "渠道", value: source)
                        }
                        if viewModel.item?.status == .wished {
                            DetailRow(label: "优先级", value: priorityName(viewModel.item?.priority))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !viewModel.recommendations.isEmpty {
                    LolitaSection(title: "推荐搭配") {
                        ForEach(viewModel.recommendations, id: \.item.id) { match in
                            NavigationLink(destination: ItemDetailScreen(itemId: match.item.id)) {
                                HStack {
                                    ItemRow(item: match.item)
                                    Spacer()
                                    Text("\(Int(match.score * 100))%")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .lolitaNavBar(
            title: "服饰详情",
            showBack: true,
            onBack: { dismiss() }
        )
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    NavigationLink(destination: PriceManageScreen(itemId: viewModel.itemId)) {
                        Image(systemName: "yensign.circle")
                    }
                    NavigationLink("编辑") {
                        ItemEditScreen(itemId: viewModel.itemId)
                    }
                }
            }
        }
        #endif
        .onAppear { Task { await viewModel.load() } }
    }

    private func priorityName(_ priority: ItemPriority?) -> String {
        switch priority {
        case .high: return "高"
        case .medium: return "中"
        case .low: return "低"
        case nil: return ""
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
            Text(value)
                .font(.subheadline)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 3)
    }
}
