import SwiftUI

struct ItemListScreen: View {
    @EnvironmentObject private var skinManager: SkinManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var deleteError: String?
    @StateObject private var viewModel = ItemListViewModel()

    private var cardColor: Color {
        colorScheme == .dark ? skinManager.current.cardColorDark : skinManager.current.cardColor
    }
    private var showsItemFilters: Bool {
        viewModel.selectedSubTab == .items || viewModel.selectedSubTab == .wishlist
    }
    private var hasFilters: Bool {
        viewModel.brandFilter != nil || viewModel.categoryFilter != nil || viewModel.statusFilter != nil
    }
    private var locations: [Location] {
        viewModel.locations.filter { viewModel.searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(viewModel.searchText) }
            .sorted { viewModel.newestFirst ? $0.updatedAt > $1.updatedAt : $0.name.localizedCompare($1.name) == .orderedAscending }
    }
    private var coordinates: [Coordinate] {
        viewModel.coordinates.filter { viewModel.searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(viewModel.searchText) }
            .sorted { viewModel.newestFirst ? $0.updatedAt > $1.updatedAt : $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            LolitaSegmentedTabs(options: ItemSubTab.allCases, selection: $viewModel.selectedSubTab, label: { $0.rawValue })
                .padding(.horizontal, 12)
                .padding(.vertical, skinManager.current.spacingM)

            if showsItemFilters && hasFilters {
                HStack {
                    Text(filterDescription).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Spacer()
                    Button("清除") { resetFilters() }.font(.caption.weight(.medium))
                }
                .padding(.horizontal, 12)
                .padding(.bottom, skinManager.current.spacingM)
            }
            Group {
                switch viewModel.selectedSubTab {
                case .location: locationTab
                case .items: itemTab(status: .owned)
                case .coordinate: coordinateTab
                case .wishlist: itemTab(status: .wished)
                }
            }
            .lolitaCollectionListStyle()
        }
        .alert("删除失败", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("确定") { deleteError = nil }
        } message: { Text(deleteError ?? "") }
        .lolitaNavBar(title: "我的衣橱")
        .searchable(text: $viewModel.searchText, prompt: "搜索\(viewModel.selectedSubTab.rawValue)")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if showsItemFilters { filterMenu }
                Menu {
                    Picker("排序", selection: $viewModel.newestFirst) {
                        Text("最近更新").tag(true)
                        Text("名称 A–Z").tag(false)
                    }
                } label: { Image(systemName: "arrow.up.arrow.down") }
                .accessibilityLabel("排序")
                NavigationLink(destination: newRecord) { Image(systemName: "plus") }
                    .accessibilityLabel("新增\(viewModel.selectedSubTab.rawValue)")
            }
        }
        .onChange(of: viewModel.selectedSubTab) { _, _ in viewModel.statusFilter = nil }
        .onAppear { viewModel.load() }
        .onDisappear { viewModel.stopObserving() }
    }

    private var filterMenu: some View {
        Menu {
            Picker("品牌", selection: $viewModel.brandFilter) {
                Text("所有品牌").tag(nil as Int64?)
                ForEach(viewModel.brands, id: \.id) { Text($0.name).tag($0.id as Int64?) }
            }
            Picker("分类", selection: $viewModel.categoryFilter) {
                Text("所有分类").tag(nil as Int64?)
                ForEach(viewModel.categories, id: \.id) { Text($0.name).tag($0.id as Int64?) }
            }
            if viewModel.selectedSubTab == .items {
                Picker("状态", selection: $viewModel.statusFilter) {
                    Text("全部").tag(nil as ItemStatus?)
                    Text("已拥有").tag(ItemStatus.owned as ItemStatus?)
                    Text("待尾款").tag(ItemStatus.pendingBalance as ItemStatus?)
                }
            }
            Button("重置筛选") { resetFilters() }
        } label: {
            Image(systemName: hasFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("筛选")
    }

    private var filterDescription: String {
        [viewModel.brands.first { $0.id == viewModel.brandFilter }?.name,
         viewModel.categories.first { $0.id == viewModel.categoryFilter }?.name,
         viewModel.statusFilter.map { $0 == .owned ? "已拥有" : "待尾款" }]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private func resetFilters() {
        viewModel.brandFilter = nil
        viewModel.categoryFilter = nil
        viewModel.statusFilter = nil
    }

    @ViewBuilder private var newRecord: some View {
        switch viewModel.selectedSubTab {
        case .location: LocationEditScreen()
        case .coordinate: CoordinateEditScreen()
        case .items: ItemEditScreen()
        case .wishlist: ItemEditScreen(defaultStatus: .wished)
        }
    }

    @ViewBuilder private var locationTab: some View {
        if locations.isEmpty {
            emptyState(title: "还没有收纳位置", symbol: "archivebox")
        } else {
            List {
                Section {
                    ForEach(locations, id: \.id) { location in
                        NavigationLink(destination: LocationDetailScreen(locationId: location.id)) {
                            LolitaCollectionRow(title: location.name,
                                                subtitle: "\(viewModel.itemsByLocation(location.id).count) 件服饰",
                                                imagePath: location.imageUrl, symbol: "archivebox")
                        }
                        .lolitaCollectionRowInsets()
                        .listRowBackground(cardColor)
                    }
                } header: { LolitaCollectionHeader(title: "收纳位置", count: locations.count) }
            }
        }
    }

    @ViewBuilder private var coordinateTab: some View {
        if coordinates.isEmpty {
            emptyState(title: "还没有套装", symbol: "photo.on.rectangle.angled")
        } else {
            List {
                Section {
                    ForEach(coordinates, id: \.id) { coordinate in
                        NavigationLink(destination: CoordinateDetailScreen(coordinateId: coordinate.id)) {
                            LolitaCollectionRow(title: coordinate.name,
                                                subtitle: coordinate.description.isEmpty ? "\(viewModel.itemsByCoordinate(coordinate.id).count) 件服饰" : coordinate.description,
                                                imagePath: coordinate.imageUrls.values.first, symbol: "photo.on.rectangle.angled")
                        }
                        .lolitaCollectionRowInsets()
                        .listRowBackground(cardColor)
                    }
                } header: { LolitaCollectionHeader(title: "我的套装", count: coordinates.count) }
            }
        }
    }

    @ViewBuilder private func itemTab(status: ItemStatus) -> some View {
        let items = viewModel.itemsByStatus(status)
        if items.isEmpty {
            emptyState(title: status == .wished ? "心愿清单还是空的" : "衣橱里还没有服饰", symbol: status == .wished ? "heart" : "tshirt")
        } else {
            List {
                Section {
                    ForEach(items, id: \.id) { item in
                        NavigationLink(destination: ItemDetailScreen(itemId: item.id)) {
                            ItemRow(item: item, brandName: viewModel.brands.first { $0.id == item.brandId }?.name)
                        }
                        .lolitaCollectionRowInsets()
                        .listRowBackground(cardColor)
                        .swipeActions {
                            Button("删除", role: .destructive) {
                                Task {
                                    do { try await AppModule.shared.itemRepository.delete(item) }
                                    catch { deleteError = userFacingError(error) }
                                }
                            }
                        }
                    }
                } header: { LolitaCollectionHeader(title: status == .wished ? "想拥有的服饰" : "我的服饰", count: items.count) }
            }
        }
    }

    private func emptyState(title: String, symbol: String) -> some View {
        let searching = !viewModel.searchText.isEmpty || (showsItemFilters && hasFilters)
        return VStack(spacing: 16) {
            LolitaEmptyState(title: searching ? "没有找到匹配结果" : title,
                             message: searching ? "试试其他关键词，或调整筛选条件。" : "点下方按钮，记录你的第一项收藏。",
                             systemImage: searching ? "magnifyingglass" : symbol, fillsAvailableSpace: false)
            if searching {
                Button("清除搜索与筛选") { viewModel.searchText = ""; resetFilters() }
                    .buttonStyle(.bordered)
            } else {
                NavigationLink(destination: newRecord) { Label("新增\(viewModel.selectedSubTab.rawValue)", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 24)
    }
}

// Shared by collection, search results and item selection.
struct ItemRow: View {
    let item: Item
    var brandName: String? = nil

    private var metadata: String {
        [brandName, item.style, item.size].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 14) {
            LolitaThumbnail(path: item.imageUrls.values.first, symbol: "tshirt")
            VStack(alignment: .leading, spacing: 6) {
                Text(item.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !metadata.isEmpty {
                    Text(metadata).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                if item.status == .pendingBalance {
                    LolitaBadge(text: "待尾款", color: .orange)
                } else if item.status == .wished {
                    LolitaBadge(text: priorityLabel, color: priorityColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
    }

    private var priorityLabel: String {
        switch item.priority { case .high: return "高优先"; case .medium: return "中优先"; case .low: return "低优先" }
    }
    private var priorityColor: Color {
        switch item.priority { case .high: return .pink; case .medium: return .orange; case .low: return .green }
    }
}
