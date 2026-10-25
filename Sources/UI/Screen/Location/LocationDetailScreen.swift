import SwiftUI

struct LocationDetailScreen: View {
    @StateObject private var viewModel: LocationDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var skinManager: SkinManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var showPicker = false
    @State private var showDelete = false
    @State private var operationError: String?
    @State private var reloadToken = 0

    init(locationId: Int64) { _viewModel = StateObject(wrappedValue: LocationDetailViewModel(locationId: locationId)) }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: skinManager.current.spacingL) {
                if viewModel.isLoading {
                    DetailLoadState(isLoading: true, message: "正在加载") {}
                } else if let error = viewModel.errorMessage {
                    DetailLoadState(isLoading: false, message: error) { reloadToken += 1 }
                } else {
                    if let path = viewModel.location?.imageUrl, !path.isEmpty { ImageGalleryPager(urls: [ImageFileHelper.fileURL(for: path)]) }
                    DetailTitleCard(title: viewModel.title, subtitle: viewModel.isUnassigned ? "尚未选择收纳位置的服饰" : "") {
                        LolitaBadge(text: "\(viewModel.items.count) 件服饰", color: detailAccent(skinManager.current, colorScheme: colorScheme))
                    }
                    if let description = viewModel.location?.description, !description.isEmpty {
                        LolitaSection(title: "位置说明") { Text(description).font(.body).fixedSize(horizontal: false, vertical: true) }
                    }
                    if !viewModel.isUnassigned {
                        NavigationLink("管理分层收纳") { StorageManageScreen(roomId: viewModel.locationId) }
                            .accessibilityIdentifier("manage-storage")
                    }
                    HStack {
                        Text(viewModel.isUnassigned ? "待分配服饰" : "存放服饰").font(.headline)
                        Spacer()
                        Button { showPicker = true } label: {
                            SkinLabel(viewModel.isUnassigned ? "分配位置" : "管理", systemImage: viewModel.isUnassigned ? "archivebox" : "plus")
                        }.font(.subheadline)
                        .disabled(viewModel.isUnassigned && viewModel.items.isEmpty)
                    }.padding(.horizontal, 4)
                    if viewModel.items.isEmpty {
                        LolitaCard {
                            SkinLabel(viewModel.isUnassigned ? "所有服饰都已分配位置" : "这里还没有存放服饰", systemImage: "archivebox")
                                .font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        ForEach(viewModel.items, id: \.id) { item in
                            NavigationLink(destination: ItemDetailScreen(itemId: item.id)) {
                                DetailRelatedItemCard(item: item, brandName: viewModel.brandNames[item.brandId] ?? "", categoryName: viewModel.categoryNames[item.categoryId] ?? "")
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(skinManager.current.spacingL)
        }
        .lolitaNavBar(title: viewModel.title, showBack: true)
        .task(id: reloadToken) { await viewModel.load() }
        .toolbar {
            #if os(iOS)
            ToolbarItemGroup(placement: .topBarTrailing) { toolbarActions }
            #else
            ToolbarItemGroup(placement: .automatic) { toolbarActions }
            #endif
        }
        .sheet(isPresented: $showPicker) {
            LocationDetailItemPicker(viewModel: viewModel).environmentObject(skinManager)
        }
        .alert("删除这个收纳位置？", isPresented: $showDelete) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                Task {
                    do { try await viewModel.delete(); dismiss() }
                    catch { operationError = userFacingError(error) }
                }
            }
        } message: { Text("房间及下级收纳位置将删除；物品、账本和照片会保留，并移至未设置位置。") }
        .alert("操作失败", isPresented: Binding(get: { operationError != nil }, set: { if !$0 { operationError = nil } })) {
            Button("确定") { operationError = nil }
        } message: { Text(operationError ?? "") }
    }

    @ViewBuilder private var toolbarActions: some View {
        if !viewModel.isUnassigned, viewModel.location != nil {
            NavigationLink(destination: LocationEditScreen(locationId: viewModel.locationId, onSave: { await viewModel.load() })) {
                SkinIcon(systemName: "pencil")
            }.accessibilityLabel("编辑位置")
            Menu {
                SkinButton("管理存放服饰", systemImage: "hanger") { showPicker = true }
                SkinButton("删除位置", systemImage: "trash", role: .destructive) { showDelete = true }
            } label: { SkinIcon(systemName: "ellipsis") }
                .accessibilityLabel("更多位置操作")
                .accessibilityIdentifier("location-more-actions")
        }
    }
}

private struct LocationDetailItemPicker: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: LocationDetailViewModel
    @State private var selectedIds: Set<Int64>
    @State private var destinationId: Int64?
    @State private var search = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(viewModel: LocationDetailViewModel) {
        self.viewModel = viewModel
        _selectedIds = State(initialValue: viewModel.isUnassigned ? [] : Set(viewModel.items.map(\.id)))
        _destinationId = State(initialValue: viewModel.locations.first?.id)
    }
    private var candidates: [Item] {
        (viewModel.isUnassigned ? viewModel.items : viewModel.allItems)
            .filter { $0.status == .owned || selectedIds.contains($0.id) }
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || (viewModel.brandNames[$0.brandId] ?? "").localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                if viewModel.isUnassigned {
                    Section("放入位置") {
                        if viewModel.locations.isEmpty {
                            NavigationLink(destination: LocationEditScreen(onSave: { await viewModel.load() })) {
                                SkinLabel("先创建收纳位置", systemImage: "plus.circle")
                            }
                        } else {
                            Picker("收纳位置", selection: $destinationId) {
                                Text("请选择").tag(nil as Int64?)
                                ForEach(viewModel.locations, id: \.id) { location in Text(location.name).tag(location.id as Int64?) }
                            }
                        }
                    }
                }
                Section {
                    ForEach(candidates, id: \.id) { item in
                        Button {
                            if !selectedIds.insert(item.id).inserted { selectedIds.remove(item.id) }
                        } label: {
                            HStack(spacing: 10) {
                                LolitaThumbnail(path: item.imageUrls.values.first, symbol: "hanger", width: 40, height: 50)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name).font(.subheadline).foregroundStyle(.primary)
                                    Text("当前：\(item.locationId.flatMap { viewModel.locationNames[$0] } ?? "未分配")")
                                        .font(.caption).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                SkinIcon(systemName: selectedIds.contains(item.id) ? "checkmark.circle.fill" : "circle")
                            }
                        }.accessibilityAddTraits(selectedIds.contains(item.id) ? .isSelected : [])
                    }
                } header: { Text("已选 \(selectedIds.count) 件") }
                  footer: { Text(viewModel.isUnassigned ? "选择服饰后，统一放入上方位置。" : "勾选服饰放入此位置；取消勾选会将原有服饰转为未分配。") }
            }
            .searchable(text: $search, prompt: "搜索服饰或品牌")
            .lolitaNavBar(title: viewModel.isUnassigned ? "分配收纳位置" : "管理存放服饰")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(isSaving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "保存中" : "保存") {
                        isSaving = true
                        Task {
                            do {
                                if viewModel.isUnassigned {
                                    guard let destinationId else { throw ValidationError.invalid("请选择收纳位置") }
                                    try await viewModel.assign(selectedIds, to: destinationId)
                                } else { try await viewModel.saveMembership(selectedIds) }
                                dismiss()
                            } catch { errorMessage = userFacingError(error); isSaving = false }
                        }
                    }.disabled(isSaving || (viewModel.isUnassigned && (selectedIds.isEmpty || destinationId == nil)))
                }
            }
            .interactiveDismissDisabled(isSaving)
            .alert("保存失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("确定") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }
}
