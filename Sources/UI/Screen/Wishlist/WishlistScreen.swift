import SwiftUI

struct WishlistScreen: View {
    @AppStorage("wishlistViewMode") private var viewMode: LolitaCollectionViewMode = .list
    @AppStorage("showTotalPrice") private var showTotalPrice = true
    @State private var deleteError: String?
    @State private var deleteRequest: LolitaDeleteRequest?
    @StateObject private var viewModel = ItemListViewModel()

    private var items: [Item] { viewModel.wishlistByPriority() }
    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading { LolitaCollectionSkeletons(mode: viewMode) }
            else if items.isEmpty {
                VStack(spacing: 16) {
                    LolitaEmptyState(title: viewModel.searchText.isEmpty ? "心愿清单还是空的" : "没有找到匹配结果",
                                     message: viewModel.searchText.isEmpty ? "记下喜欢的服饰，慢慢实现每一个心愿。" : "试试其他名称或关键词。",
                                     systemImage: viewModel.searchText.isEmpty ? "heart" : "magnifyingglass", fillsAvailableSpace: false)
                    if viewModel.searchText.isEmpty {
                        NavigationLink(destination: ItemEditScreen(defaultStatus: .wished)) { Label("添加心愿", systemImage: "plus") }.buttonStyle(.borderedProminent)
                    } else { Button("清除搜索") { viewModel.searchText = "" }.buttonStyle(.bordered) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(.bottom, 24)
            } else {
                LolitaCollectionControls(count: items.count, detail: "按优先级排列 · \(items.filter { $0.priority == .high }.count) 件高优先", totalPrice: showTotalPrice ? viewModel.totalPrice(of: items) : nil, mode: $viewMode)
                if viewMode == .list {
                    List {
                        ForEach(items, id: \.id) { item in
                            card(item).lolitaCardRow().swipeActions { Button("删除", role: .destructive) { delete(item) } }
                        }
                    }.lolitaCardListStyle()
                } else {
                    LolitaCollectionGrid(mode: viewMode) { ForEach(items, id: \.id) { item in card(item) } }
                }
            }
        }
        .searchable(text: $viewModel.searchText, prompt: "搜索心愿服饰")
        .lolitaNavBar(title: "愿望单")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(destination: ItemEditScreen(defaultStatus: .wished)) { Image(systemName: "plus") }.accessibilityLabel("添加心愿")
            }
        }
        .alert("删除失败", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("确定") { deleteError = nil }
        } message: { Text(deleteError ?? "") }
        .lolitaDeleteConfirmation($deleteRequest)
        .onAppear { viewModel.load() }
        .onDisappear { viewModel.stopObserving() }
    }
    private func card(_ item: Item) -> some View {
        NavigationLink(destination: ItemDetailScreen(itemId: item.id)) {
            ItemCollectionCard(item: item, brandName: viewModel.brands.first { $0.id == item.brandId }?.name,
                               brandLogoPath: viewModel.brands.first { $0.id == item.brandId }?.logoUrl,
                               categoryName: viewModel.categories.first { $0.id == item.categoryId }?.name,
                               price: showTotalPrice ? viewModel.pricesByItem[item.id] : nil, mode: viewMode)
        }.buttonStyle(.plain)
        .contextMenu {
            NavigationLink(destination: ItemEditScreen(itemId: item.id)) { Label("编辑", systemImage: "pencil") }
            Button("删除", role: .destructive) { delete(item) }
        }
    }
    private func delete(_ item: Item) {
        deleteRequest = LolitaDeleteRequest(name: item.name) {
            Task { do { try await viewModel.delete(item) } catch { deleteError = userFacingError(error) } }
        }
    }
}
