import SwiftUI

struct CoordinateListScreen: View {
    @AppStorage("coordinateViewMode") private var viewMode: LolitaCollectionViewMode = .grid
    @AppStorage("showTotalPrice") private var showTotalPrice = true
    @AppStorage("coordinateSortOption") private var sort: CollectionSortOption = .updatedNewest
    @State private var deleteError: String?
    @State private var deleteRequest: LolitaDeleteRequest?
    @StateObject private var viewModel = ItemListViewModel()
    @State private var search = ""

    private var coordinates: [Coordinate] {
        sort.sorted(viewModel.coordinates.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.description.localizedCaseInsensitiveContains(search) }) {
            CollectionSortKey(id: $0.id, name: $0.name, updatedAt: $0.updatedAt, price: viewModel.totalPrice(of: viewModel.itemsByCoordinate($0.id)))
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            if coordinates.isEmpty {
                VStack(spacing: 16) {
                    LolitaEmptyState(title: search.isEmpty ? "还没有套装" : "没有找到匹配结果",
                                     message: search.isEmpty ? "把喜欢的服饰组合在一起，收藏你的搭配灵感。" : "试试其他名称或关键词。",
                                     systemImage: search.isEmpty ? "photo.on.rectangle.angled" : "magnifyingglass", fillsAvailableSpace: false)
                    if search.isEmpty {
                        NavigationLink(destination: CoordinateEditScreen()) { Label("创建套装", systemImage: "plus") }.buttonStyle(.borderedProminent)
                    } else { Button("清除搜索") { search = "" }.buttonStyle(.bordered) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                LolitaCollectionControls(count: coordinates.count, unit: "套", mode: $viewMode)
                if viewMode == .list {
                    List {
                        ForEach(coordinates, id: \.id) { coordinate in
                            card(coordinate).lolitaCardRow().swipeActions {
                                Button("删除", role: .destructive) { delete(coordinate) }
                            }
                        }
                    }.lolitaCardListStyle()
                } else {
                    LolitaCollectionGrid(mode: viewMode) { ForEach(coordinates, id: \.id) { coordinate in card(coordinate) } }
                }
            }
        }
        .searchable(text: $search, prompt: "搜索套装")
        .lolitaNavBar(title: "套装")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                LolitaCollectionSortMenu(selection: $sort)
                NavigationLink(destination: CoordinateEditScreen()) { Image(systemName: "plus") }.accessibilityLabel("创建套装")
            }
        }
        .alert("删除失败", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("确定") { deleteError = nil }
        } message: { Text(deleteError ?? "") }
        .lolitaDeleteConfirmation($deleteRequest)
        .onAppear { viewModel.load() }
        .onDisappear { viewModel.stopObserving() }
    }
    private func card(_ coordinate: Coordinate) -> some View {
        let items = viewModel.itemsByCoordinate(coordinate.id)
        return NavigationLink(destination: CoordinateDetailScreen(coordinateId: coordinate.id)) {
            CoordinateCollectionCard(coordinate: coordinate, items: items, price: showTotalPrice ? viewModel.totalPrice(of: items) : nil, mode: viewMode)
        }.buttonStyle(.plain)
        .contextMenu {
            NavigationLink(destination: CoordinateEditScreen(coordinateId: coordinate.id)) { Label("编辑", systemImage: "pencil") }
            Button("删除", role: .destructive) { delete(coordinate) }
        }
    }
    private func delete(_ coordinate: Coordinate) {
        deleteRequest = LolitaDeleteRequest(name: coordinate.name) {
            Task { do { try await AppModule.shared.coordinateRepository.delete(coordinate) } catch { deleteError = userFacingError(error) } }
        }
    }
}
