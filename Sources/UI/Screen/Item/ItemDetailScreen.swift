import SwiftUI

struct ItemDetailScreen: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var skin: DefaultSkin
    @StateObject private var viewModel: ItemDetailViewModel

    init(itemId: Int64) {
        _viewModel = StateObject(wrappedValue: ItemDetailViewModel(itemId: itemId))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: skin.cardGap) {
                ImageGalleryPager(urls: viewModel.imageUrls)

                LolitaCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(viewModel.item?.name ?? "")
                            .font(.title2.weight(.bold))

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
                        DetailRow(label: "优先级", value: priorityName(viewModel.item?.priority))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !viewModel.recommendations.isEmpty {
                    LolitaSection(title: "推荐搭配") {
                        ForEach(viewModel.recommendations, id: \.item.id) { match in
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
            .padding()
        }
        .lolitaNavBar(
            title: viewModel.item?.name ?? "服饰详情",
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
        .task { await viewModel.load() }
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

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
        }
    }
}
