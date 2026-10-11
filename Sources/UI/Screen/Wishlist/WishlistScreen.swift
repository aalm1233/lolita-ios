import SwiftUI

struct WishlistScreen: View {
    @EnvironmentObject private var skinManager: SkinManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var deleteError: String?
    @StateObject private var viewModel = WishlistViewModel()

    var body: some View {
        Group {
            if viewModel.prioritizedItems().isEmpty {
                VStack(spacing: 16) {
                    LolitaEmptyState(title: viewModel.searchText.isEmpty ? "心愿清单还是空的" : "没有找到匹配结果",
                                     message: viewModel.searchText.isEmpty ? "记下喜欢的服饰，慢慢实现每一个心愿。" : "试试其他名称或关键词。",
                                     systemImage: viewModel.searchText.isEmpty ? "heart" : "magnifyingglass",
                                     fillsAvailableSpace: false)
                    if viewModel.searchText.isEmpty {
                        NavigationLink(destination: ItemEditScreen(defaultStatus: .wished)) { Label("添加心愿", systemImage: "plus") }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button("清除搜索") { viewModel.searchText = "" }.buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, 24)
            } else {
                List {
                    Section {
                        ForEach(viewModel.prioritizedItems(), id: \.id) { item in
                            NavigationLink(destination: ItemDetailScreen(itemId: item.id)) { ItemRow(item: item) }
                                .lolitaCollectionRowInsets()
                                .listRowBackground(colorScheme == .dark ? skinManager.current.cardColorDark : skinManager.current.cardColor)
                                .swipeActions {
                                    Button(role: .destructive) {
                                        Task {
                                            do { try await viewModel.delete(item) }
                                            catch { deleteError = userFacingError(error) }
                                        }
                                    } label: { Label("删除", systemImage: "trash") }
                                }
                        }
                    } header: { LolitaCollectionHeader(title: "按优先级排列", count: viewModel.prioritizedItems().count) }
                }
                .lolitaCollectionListStyle()
            }
        }
        .searchable(text: $viewModel.searchText, prompt: "搜索心愿服饰")
        .lolitaNavBar(title: "愿望单")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(destination: ItemEditScreen(defaultStatus: .wished)) { Image(systemName: "plus") }
                    .accessibilityLabel("添加心愿")
            }
        }
        .alert("删除失败", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("确定") { deleteError = nil }
        } message: { Text(deleteError ?? "") }
        .onAppear { viewModel.load() }
        .onDisappear { viewModel.stopObserving() }
    }
}
