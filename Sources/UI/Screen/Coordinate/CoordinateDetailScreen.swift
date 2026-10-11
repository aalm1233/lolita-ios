import SwiftUI

struct CoordinateDetailScreen: View {
    @EnvironmentObject private var skinManager: SkinManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = CoordinateDetailViewModel()
    @State private var showDelete = false
    @State private var showItemPicker = false
    @State private var operationError: String?
    @State private var reloadToken = 0
    let coordinateId: Int64

    var body: some View {
        ScrollView {
            LazyVStack(spacing: skinManager.current.spacingL) {
                if let coordinate = viewModel.coordinate {
                    if !viewModel.imageUrls.isEmpty { ImageGalleryPager(urls: viewModel.imageUrls) }
                    DetailTitleCard(title: coordinate.name) {
                        LolitaBadge(text: "\(viewModel.items.count) 件服饰", color: detailAccent(skinManager.current, colorScheme: colorScheme))
                    }
                    if !coordinate.description.isEmpty {
                        LolitaSection(title: "描述") { Text(coordinate.description).font(.body).fixedSize(horizontal: false, vertical: true) }
                    }
                    LolitaSection(title: "价格汇总") {
                        if viewModel.pricesByItem.values.allSatisfy({ $0.isEmpty }) {
                            Text("关联服饰尚未记录价格").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 8)
                        } else {
                            DetailMoneySummary(total: viewModel.totalPrice, paid: viewModel.paidAmount, unpaid: viewModel.unpaidAmount)
                        }
                    }
                    HStack {
                        Text("包含服饰 · \(viewModel.items.count) 件").font(.headline)
                        Spacer()
                        Button { showItemPicker = true } label: { Label("管理", systemImage: "plus") }.font(.subheadline)
                    }.padding(.horizontal, 4)
                    if viewModel.items.isEmpty {
                        LolitaCard { Text("选择服饰，组合成完整的搭配。").font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
                    } else {
                        ForEach(viewModel.items, id: \.id) { item in
                            NavigationLink(destination: ItemDetailScreen(itemId: item.id)) {
                                DetailRelatedItemCard(item: item, brandName: viewModel.brandNames[item.brandId] ?? "",
                                                      categoryName: viewModel.categoryNames[item.categoryId] ?? "",
                                                      price: viewModel.pricesByItem[item.id].map { $0.reduce(0) { $0 + $1.price.totalPrice } })
                            }.buttonStyle(.plain)
                        }
                    }
                    LolitaSection(title: "记录信息") {
                        DetailRow(label: "创建时间", value: detailDate(coordinate.createdAt))
                        Divider()
                        DetailRow(label: "更新时间", value: detailDate(coordinate.updatedAt))
                    }
                } else {
                    DetailLoadState(isLoading: viewModel.isLoading, message: viewModel.errorMessage ?? "套装已不存在") { reloadToken += 1 }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(skinManager.current.spacingL)
        }
        .lolitaNavBar(title: "套装详情", showBack: true)
        .toolbar {
            #if os(iOS)
            ToolbarItemGroup(placement: .topBarTrailing) { toolbarActions }
            #else
            ToolbarItemGroup(placement: .automatic) { toolbarActions }
            #endif
        }
        .task(id: reloadToken) { await viewModel.load(coordinateId: coordinateId) }
        .sheet(isPresented: $showItemPicker) {
            CoordinateDetailItemPicker(items: viewModel.allItems, initialIds: viewModel.items.map(\.id), onSave: viewModel.saveItems)
                .environmentObject(skinManager)
        }
        .alert("删除这个套装？", isPresented: $showDelete) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                Task {
                    do { try await viewModel.delete(); dismiss() }
                    catch { operationError = userFacingError(error) }
                }
            }
        } message: { Text("套装将被删除，包含的服饰会保留并解除套装关联。") }
        .alert("操作失败", isPresented: Binding(get: { operationError != nil }, set: { if !$0 { operationError = nil } })) {
            Button("确定") { operationError = nil }
        } message: { Text(operationError ?? "") }
    }

    @ViewBuilder private var toolbarActions: some View {
        if viewModel.coordinate != nil {
            NavigationLink(destination: CoordinateEditScreen(coordinateId: coordinateId)) { Image(systemName: "pencil") }
                .accessibilityLabel("编辑套装")
            Menu {
                Button("管理服饰与顺序", systemImage: "list.bullet") { showItemPicker = true }
                Button("删除套装", systemImage: "trash", role: .destructive) { showDelete = true }
            } label: { Image(systemName: "ellipsis") }
        }
    }
}

private struct CoordinateDetailItemPicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIds: [Int64]
    @State private var search = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    let items: [Item]
    let onSave: ([Int64]) async throws -> Void

    init(items: [Item], initialIds: [Int64], onSave: @escaping ([Int64]) async throws -> Void) {
        self.items = items
        self.onSave = onSave
        _selectedIds = State(initialValue: initialIds)
    }

    private var names: [Int64: Item] { Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) }) }
    private var available: [Item] { items.filter { !selectedIds.contains($0.id) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) } }

    var body: some View {
        NavigationStack {
            List {
                Section("已选服饰 · \(selectedIds.count) 件") {
                    if selectedIds.isEmpty { Text("从下方添加服饰").foregroundStyle(.secondary) }
                    ForEach(selectedIds, id: \.self) { id in
                        if let item = names[id] {
                            HStack(spacing: 10) {
                                LolitaThumbnail(path: item.imageUrls.values.first, symbol: "hanger", width: 40, height: 50)
                                Text(item.name).font(.subheadline)
                            }
                        }
                    }
                    .onMove { source, target in selectedIds.move(fromOffsets: source, toOffset: target) }
                    .onDelete { offsets in selectedIds.remove(atOffsets: offsets) }
                }
                Section("可添加服饰") {
                    ForEach(available, id: \.id) { item in
                        Button { selectedIds.append(item.id) } label: {
                            HStack(spacing: 10) {
                                LolitaThumbnail(path: item.imageUrls.values.first, symbol: "hanger", width: 40, height: 50)
                                Text(item.name).font(.subheadline).foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "plus.circle")
                            }
                        }
                        .deleteDisabled(true)
                        .moveDisabled(true)
                    }
                }
            }
            .searchable(text: $search, prompt: "搜索可添加的服饰")
            .lolitaNavBar(title: "套装服饰与顺序")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(isSaving) }
                #if os(iOS)
                ToolbarItem(placement: .bottomBar) { EditButton() }
                #endif
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "保存中" : "保存") {
                        isSaving = true
                        Task {
                            do { try await onSave(selectedIds); dismiss() }
                            catch { errorMessage = userFacingError(error); isSaving = false }
                        }
                    }.disabled(isSaving)
                }
            }
            .interactiveDismissDisabled(isSaving)
            .alert("保存失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("确定") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }
}
