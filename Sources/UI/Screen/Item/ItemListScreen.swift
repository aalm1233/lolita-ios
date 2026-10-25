import SwiftUI

struct ItemListScreen: View {
    @EnvironmentObject private var skinManager: SkinManager
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("wardrobeViewMode") private var viewMode: LolitaCollectionViewMode = .grid
    @AppStorage("showTotalPrice") private var showTotalPrice = true
    @State private var deleteError: String?
    @State private var deleteRequest: LolitaDeleteRequest?
    @State private var showFilters = false
    @State private var isSearching = false
    @FocusState private var searchFocused: Bool
    @State private var galleryPreview: CollectionGalleryPreview?
    @State private var pendingGalleryDetailID: Int64?
    @State private var galleryDetailID: Int64?
    @StateObject private var viewModel = ItemListViewModel()

    private var showsItemFilters: Bool { viewModel.selectedSubTab == .items || viewModel.selectedSubTab == .wishlist }
    private var locations: [Location] {
        viewModel.sortOption.sorted(viewModel.locations.filter { viewModel.searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(viewModel.searchText) }) {
            CollectionSortKey(id: $0.id, name: $0.name, updatedAt: $0.updatedAt, price: viewModel.totalPrice(of: viewModel.itemsByLocation($0.id)))
        }
    }
    private var coordinates: [Coordinate] {
        viewModel.sortOption.sorted(viewModel.coordinates.filter { viewModel.searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(viewModel.searchText) }) {
            CollectionSortKey(id: $0.id, name: $0.name, updatedAt: $0.updatedAt, price: viewModel.totalPrice(of: viewModel.itemsByCoordinate($0.id)))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            homeToolbar.padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 2)
                .background { SkinTopBarBackground() }
            if viewModel.selectedSubTab == .location {
                todayOutfitLink.padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 4)
            }
            PurchaseReviewShortcut().padding(.horizontal, 12)
            if viewModel.selectedSubTab == .items { categoryGroupFilters }
            if showsItemFilters && viewModel.activeFilterCount > 0 {
                HStack {
                    Text(filterDescription).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Spacer(minLength: 4)
                    Button("清除") { viewModel.resetFilters() }.font(.caption.weight(.medium))
                }.padding(.horizontal, 12).padding(.vertical, 4)
            }
            Group {
                switch viewModel.selectedSubTab {
                case .location: locationTab
                case .items: itemTab(status: .owned)
                case .coordinate: coordinateTab
                case .wishlist: itemTab(status: .wished)
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(DragGesture(minimumDistance: 28).onEnded { value in
                changeSubTab(horizontal: value.translation.width, vertical: value.translation.height)
            })
        }
        .overlay(alignment: .bottomTrailing) {
            NavigationLink(destination: newRecord) {
                SkinIcon(systemName: "plus", size: 22)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(colorScheme == .dark ? skinManager.current.primaryColorDark : skinManager.current.primaryColor,
                                in: RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("新增\(viewModel.selectedSubTab.rawValue)")
            .padding(16)
        }
        .alert("删除失败", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("确定") { deleteError = nil }
        } message: { Text(deleteError ?? "") }
        .sheet(isPresented: $showFilters) { filterSheet }
        #if os(iOS)
        .fullScreenCover(item: $galleryPreview, onDismiss: finishGalleryDismissal) { preview in
            FullScreenImageViewer(galleryEntries: preview.entries, initialIndex: preview.initialIndex) { itemID in
                pendingGalleryDetailID = itemID
                galleryPreview = nil
            }
        }
        #else
        .sheet(item: $galleryPreview, onDismiss: finishGalleryDismissal) { preview in
            FullScreenImageViewer(galleryEntries: preview.entries, initialIndex: preview.initialIndex) { itemID in
                pendingGalleryDetailID = itemID
                galleryPreview = nil
            }.frame(minWidth: 600, minHeight: 700)
        }
        #endif
        .navigationDestination(item: $galleryDetailID) { ItemDetailScreen(itemId: $0) }
        .lolitaDeleteConfirmation($deleteRequest)
        .lolitaNavBar(title: "", isHidden: true)
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: viewModel.selectedSubTab) { _, _ in viewModel.statusFilter = nil }
        .onAppear { viewModel.load() }
        .onDisappear { searchFocused = false; viewModel.stopObserving() }
    }

    private var homeToolbar: some View {
        LolitaHomeToolbar(isSearching: isSearching, onSearch: {
            withAnimation(.easeInOut(duration: 0.18)) { isSearching = true }
        }, onCancel: {
            searchFocused = false
            viewModel.searchText = ""
            withAnimation(.easeInOut(duration: 0.18)) { isSearching = false }
        }, clearSearch: viewModel.searchText.isEmpty ? nil : {
            viewModel.searchText = ""
            searchFocused = true
        }) {
            LolitaPageTabs(options: ItemSubTab.allCases, selection: $viewModel.selectedSubTab,
                           label: { $0.rawValue }, compact: true)
        } actions: {
            if showsItemFilters {
                Button { showFilters = true } label: {
                    SkinIcon(systemName: viewModel.activeFilterCount > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .frame(width: 36, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("筛选，已选 \(viewModel.activeFilterCount) 项")
            }
            if viewModel.selectedSubTab == .items || viewModel.selectedSubTab == .coordinate {
                LolitaCollectionSortMenu(selection: $viewModel.sortOption, includesPrice: showTotalPrice, buttonSize: 36)
                Button {
                    let modes = LolitaCollectionViewMode.allCases
                    let index = modes.firstIndex(of: viewMode) ?? 0
                    viewMode = modes[(index + 1) % modes.count]
                } label: {
                    SkinIcon(systemName: viewMode.symbol)
                        .frame(width: 36, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("展示方式：\(viewMode.title)，点击切换")
            }
        } searchField: {
            TextField("搜索\(viewModel.selectedSubTab.rawValue)", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .focused($searchFocused)
                .task { searchFocused = true }
                .onSubmit { searchFocused = false }
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                #endif
                .accessibilityLabel("搜索\(viewModel.selectedSubTab.rawValue)")
        }
    }

    private var todayOutfitLink: some View {
        NavigationLink(destination: QuickOutfitLogScreen()) {
            LolitaCard(variant: .compact) {
                HStack(spacing: 8) {
                    if let log = viewModel.todayOutfit {
                        LolitaLinkedItemImages(items: viewModel.itemsByOutfit(log.id))
                        Text("编辑今日穿搭").font(.subheadline.weight(.medium))
                    } else {
                        SkinIcon(systemName: "plus.circle")
                        Text("记录今日穿搭").font(.subheadline.weight(.medium))
                    }
                    Spacer(minLength: 4)
                    SkinIcon(systemName: "chevron.right", size: 12).foregroundStyle(.secondary)
                }.foregroundStyle(colorScheme == .dark ? skinManager.current.accentColorDark : skinManager.current.accentColor)
            }
        }.buttonStyle(.plain).accessibilityIdentifier("home-today-outfit")
            .accessibilityValue(viewModel.todayOutfit == nil ? "尚未记录" : "已记录")
    }

    private var categoryGroupFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                groupChip("全部", group: nil)
                groupChip("服装", group: .clothing)
                groupChip("小物", group: .accessory)
                Button {
                    viewModel.statusFilter = viewModel.statusFilter == .pendingBalance ? nil : .pendingBalance
                } label: {
                    filterChip("待尾款", selected: viewModel.statusFilter == .pendingBalance)
                }.buttonStyle(.plain)
            }.padding(.horizontal, 12).padding(.vertical, 4)
        }
    }
    private func groupChip(_ title: String, group: CategoryGroup?) -> some View {
        Button { viewModel.groupFilter = group } label: { filterChip(title, selected: viewModel.groupFilter == group) }.buttonStyle(.plain)
    }
    private func filterChip(_ title: String, selected: Bool) -> some View {
        let accent = colorScheme == .dark ? skinManager.current.accentColorDark : skinManager.current.accentColor
        return Text(title).font(.caption.weight(selected ? .semibold : .regular))
            .foregroundStyle(selected ? accent : .secondary)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(selected ? accent.opacity(0.14) : accent.opacity(0.04), in: Capsule())
            .overlay(Capsule().stroke(selected ? accent.opacity(0.4) : accent.opacity(0.12), lineWidth: 0.5))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var filterSheet: some View {
        NavigationStack {
            Form {
                Section("品牌与分类") {
                    SearchableRecordPicker(title: "品牌", options: [PickerRecord(id: 0, name: "所有品牌")] + viewModel.brands.map { PickerRecord(id: $0.id, name: $0.name) }, selection: optionalId($viewModel.brandFilter))
                    SearchableRecordPicker(title: "分类", options: [PickerRecord(id: 0, name: "所有分类")] + viewModel.categories.map { PickerRecord(id: $0.id, name: $0.name) }, selection: optionalId($viewModel.categoryFilter))
                }
                Section("服饰属性") {
                    stringFilter("季节", options: viewModel.availableSeasons, selection: $viewModel.seasonFilter)
                    stringFilter("风格", options: viewModel.availableStyles, selection: $viewModel.styleFilter)
                    stringFilter("颜色", options: viewModel.availableColors, selection: $viewModel.colorFilter)
                    if viewModel.selectedSubTab == .items {
                        Picker("状态", selection: $viewModel.statusFilter) {
                            Text("全部").tag(nil as ItemStatus?)
                            Text("已拥有").tag(ItemStatus.owned as ItemStatus?)
                            Text("待尾款").tag(ItemStatus.pendingBalance as ItemStatus?)
                            Text("待付款").tag(ItemStatus.pendingPayment as ItemStatus?)
                            Text("待核对").tag(ItemStatus.pendingReview as ItemStatus?)
                        }
                    }
                }
                Section { Button("重置筛选") { viewModel.resetFilters() } }
            }
            .lolitaNavBar(title: "筛选服饰")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showFilters = false } } }
        }
    }
    private func optionalId(_ binding: Binding<Int64?>) -> Binding<Int64> {
        Binding(get: { binding.wrappedValue ?? 0 }, set: { binding.wrappedValue = $0 == 0 ? nil : $0 })
    }
    private func stringFilter(_ title: String, options: [String], selection: Binding<String?>) -> some View {
        Picker(title, selection: selection) {
            Text("不限").tag(nil as String?)
            ForEach(options, id: \.self) { Text($0).tag($0 as String?) }
        }
    }
    private var filterDescription: String {
        [viewModel.brands.first { $0.id == viewModel.brandFilter }?.name,
         viewModel.categories.first { $0.id == viewModel.categoryFilter }?.name,
         viewModel.groupFilter.map { $0 == .clothing ? "服装" : "小物" },
         viewModel.statusFilter.map(\.displayName),
         viewModel.seasonFilter, viewModel.styleFilter, viewModel.colorFilter].compactMap { $0 }.joined(separator: " · ")
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
        let unassigned = viewModel.items.filter {
            $0.locationId == nil && (viewModel.searchText.isEmpty || "未分配".localizedCaseInsensitiveContains(viewModel.searchText))
        }
        if locations.isEmpty && unassigned.isEmpty { emptyState(title: "还没有收纳位置", symbol: "archivebox") }
        else {
            VStack(spacing: 0) {
                LolitaCollectionControls(count: locations.count + (unassigned.isEmpty ? 0 : 1), unit: "个位置", mode: $viewMode)
                LolitaCollectionGrid(mode: viewMode, bottomPadding: 88) {
                    if !unassigned.isEmpty {
                        NavigationLink(destination: LocationDetailScreen(locationId: -1)) {
                            LolitaCard(variant: .gallery) {
                                VStack(alignment: .leading, spacing: 0) {
                                    LolitaCollectionImage(path: unassigned.compactMap { $0.imageUrls.values.first }.first, title: "未分配", symbol: "tray", ratio: 1.2)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("未分配").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                        Text("\(unassigned.count) 件服饰").font(.caption).foregroundStyle(.secondary)
                                        LolitaLinkedItemImages(items: unassigned)
                                    }.padding(10)
                                }
                            }
                        }.buttonStyle(.plain)
                    }
                    ForEach(locations, id: \.id) { location in
                        NavigationLink(destination: LocationDetailScreen(locationId: location.id)) {
                            LolitaCard(variant: .gallery) {
                                VStack(alignment: .leading, spacing: 0) {
                                    LolitaCollectionImage(path: location.imageUrl ?? viewModel.itemsByLocation(location.id).compactMap { $0.imageUrls.values.first }.first,
                                                          title: location.name, symbol: "archivebox", ratio: 1.2)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(location.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                                        Text("\(viewModel.itemsByLocation(location.id).count) 件服饰").font(.caption).foregroundStyle(.secondary)
                                        LolitaLinkedItemImages(items: viewModel.itemsByLocation(location.id))
                                    }.padding(10)
                                }
                            }
                        }.buttonStyle(.plain).accessibilityIdentifier("location-\(location.id)")
                    }
                }
            }
        }
    }

    @ViewBuilder private var coordinateTab: some View {
        if coordinates.isEmpty { emptyState(title: "还没有套装", symbol: "photo.on.rectangle.angled") }
        else {
            VStack(spacing: 0) {
                LolitaCollectionControls(count: coordinates.count, unit: "套", mode: $viewMode)
                if viewMode == .list {
                    List { ForEach(coordinates, id: \.id) { coordinate in coordinateLink(coordinate).lolitaCardRow() } }
                        .lolitaCardListStyle()
                        .contentMargins(.bottom, 88, for: .scrollContent)
                } else {
                    LolitaCollectionGrid(mode: viewMode, bottomPadding: 88) { ForEach(coordinates, id: \.id) { coordinate in coordinateLink(coordinate) } }
                }
            }
        }
    }
    private func coordinateLink(_ coordinate: Coordinate) -> some View {
        let items = viewModel.itemsByCoordinate(coordinate.id)
        return NavigationLink(destination: CoordinateDetailScreen(coordinateId: coordinate.id)) {
            CoordinateCollectionCard(coordinate: coordinate, items: items, price: showTotalPrice ? viewModel.totalPrice(of: items) : nil, mode: viewMode)
        }.buttonStyle(.plain).accessibilityIdentifier("coordinate-\(coordinate.id)")
        .contextMenu {
            NavigationLink(destination: CoordinateEditScreen(coordinateId: coordinate.id)) { SkinLabel("编辑", systemImage: "pencil") }
            Button("删除", role: .destructive) {
                deleteRequest = LolitaDeleteRequest(name: coordinate.name) {
                    Task { do { try await AppModule.shared.coordinateRepository.delete(coordinate) } catch { deleteError = userFacingError(error) } }
                }
            }
        }
    }

    @ViewBuilder private func itemTab(status: ItemStatus) -> some View {
        let items = status == .wished ? viewModel.wishlistByPriority() : viewModel.itemsByStatus(status)
        if viewModel.isLoading { LolitaCollectionSkeletons(mode: viewMode) }
        else if items.isEmpty { emptyState(title: status == .wished ? "心愿清单还是空的" : "衣橱里还没有服饰", symbol: status == .wished ? "heart" : "tshirt") }
        else {
            VStack(spacing: 0) {
                LolitaCollectionControls(count: items.count, detail: status == .wished ? "按优先级排列" : "\(items.filter { $0.status == .owned }.count) 件已拥有 · \(items.filter { $0.status == .pendingBalance }.count) 件待尾款",
                                         totalPrice: showTotalPrice ? viewModel.totalPrice(of: items) : nil, mode: $viewMode)
                if viewMode == .list {
                    List {
                        ForEach(items, id: \.id) { item in
                            itemLink(item).lolitaCardRow()
                        }
                    }.lolitaCardListStyle()
                        .contentMargins(.bottom, 88, for: .scrollContent)
                } else {
                    LolitaCollectionGrid(mode: viewMode, bottomPadding: 88) { ForEach(items, id: \.id) { item in itemLink(item) } }
                }
            }
        }
    }
    private func itemLink(_ item: Item) -> some View {
        Group {
            if viewMode == .gallery, item.imageUrls.values.contains(where: { !$0.isEmpty }) {
                Button { openGallery(startingAt: item) } label: { itemCard(item) }
                    .accessibilityHint("轻点全屏预览，长按可查看详情或编辑")
            } else {
                NavigationLink(destination: ItemDetailScreen(itemId: item.id)) { itemCard(item) }
            }
        }.buttonStyle(.plain)
        .accessibilityIdentifier("item-\(item.id)")
        .contextMenu {
            NavigationLink(destination: ItemDetailScreen(itemId: item.id)) { SkinLabel("查看详情", systemImage: "info.circle") }
            NavigationLink(destination: ItemEditScreen(itemId: item.id)) { SkinLabel("编辑", systemImage: "pencil") }
            Button("删除", role: .destructive) { delete(item) }
        }
    }
    private func itemCard(_ item: Item) -> some View {
        let brand = viewModel.brands.first { $0.id == item.brandId }
        return ItemCollectionCard(item: item, brandName: brand?.name, brandLogoPath: brand?.logoUrl,
                                  categoryName: viewModel.categories.first { $0.id == item.categoryId }?.name,
                                  price: showTotalPrice ? viewModel.pricesByItem[item.id] : nil, mode: viewMode)
    }

    private func openGallery(startingAt item: Item) {
        let items = item.status == .wished ? viewModel.wishlistByPriority() : viewModel.itemsByStatus(.owned)
        let entries = items.compactMap { value -> GalleryImageEntry? in
            guard let path = value.imageUrls.values.first(where: { !$0.isEmpty }) else { return nil }
            return GalleryImageEntry(itemId: value.id, title: value.name, brandName: viewModel.brands.first { $0.id == value.brandId }?.name, url: ImageFileHelper.fileURL(for: path))
        }
        guard let index = entries.firstIndex(where: { $0.itemId == item.id }) else { return }
        pendingGalleryDetailID = nil
        galleryPreview = CollectionGalleryPreview(entries: entries, initialIndex: index)
    }

    private func finishGalleryDismissal() {
        if let id = pendingGalleryDetailID { pendingGalleryDetailID = nil; galleryDetailID = id }
    }

    private func changeSubTab(horizontal: CGFloat, vertical: CGFloat) {
        // Attach only to the content below the tabs; text selection in the search field stays independent.
        // A vertical scroll or diagonal movement must not change the active collection.
        guard abs(horizontal) >= 80, abs(horizontal) > abs(vertical) * 3,
              let current = ItemSubTab.allCases.firstIndex(of: viewModel.selectedSubTab) else { return }
        let next = current + (horizontal < 0 ? 1 : -1)
        guard ItemSubTab.allCases.indices.contains(next) else { return }
        withAnimation(.easeInOut(duration: 0.18)) { viewModel.selectedSubTab = ItemSubTab.allCases[next] }
    }
    private func delete(_ item: Item) {
        deleteRequest = LolitaDeleteRequest(name: item.name) {
            Task { do { try await viewModel.delete(item) } catch { deleteError = userFacingError(error) } }
        }
    }

    private func emptyState(title: String, symbol: String) -> some View {
        let searching = !viewModel.searchText.isEmpty || (showsItemFilters && viewModel.activeFilterCount > 0)
        return VStack(spacing: 16) {
            LolitaEmptyState(title: searching ? "没有找到匹配结果" : title,
                             message: searching ? "试试其他关键词，或调整筛选条件。" : "点下方按钮，记录你的第一项收藏。",
                             systemImage: searching ? "magnifyingglass" : symbol, fillsAvailableSpace: false)
            if searching { Button("清除搜索与筛选") { viewModel.searchText = ""; viewModel.resetFilters() }.buttonStyle(.bordered) }
            else {
                NavigationLink(destination: newRecord) { SkinLabel("新增\(viewModel.selectedSubTab.rawValue)", systemImage: "plus") }.buttonStyle(.borderedProminent)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(.bottom, 24)
    }
}

// Shared by collection, search results and item selection.
struct ItemRow: View {
    let item: Item
    var brandName: String? = nil
    var brandLogoPath: String? = nil
    var categoryName: String? = nil
    var price: Double? = nil
    var showsDescription = false
    private var metadata: String {
        [categoryName, item.style, item.size, item.colors.values.first].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            LolitaThumbnail(path: item.imageUrls.values.first, symbol: "tshirt", width: showsDescription ? 80 : 64, height: showsDescription ? 96 : 80)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.name).font(.body.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                if let brandName { LolitaBrandLabel(name: brandName, logoPath: brandLogoPath, font: .caption) }
                if showsDescription && !item.description.isEmpty { Text(item.description).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                if !metadata.isEmpty { Text(metadata).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
                HStack(spacing: 8) {
                    LolitaItemStatus(item: item)
                    if let price { Text(lolitaPriceLabel(price)).font(.caption.weight(.semibold)).foregroundStyle(.primary).monospacedDigit() }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, showsDescription ? 0 : 6)
    }
}

private struct CollectionGalleryPreview: Identifiable {
    let id = UUID()
    let entries: [GalleryImageEntry]
    let initialIndex: Int
}
