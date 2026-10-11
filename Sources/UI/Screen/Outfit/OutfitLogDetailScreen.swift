import SwiftUI

struct OutfitLogDetailScreen: View {
    @EnvironmentObject private var skinManager: SkinManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = OutfitLogDetailViewModel()
    @State private var removeItem: Item?
    @State private var showDelete = false
    @State private var operationError: String?
    @State private var reloadToken = 0
    let logId: Int64

    var body: some View {
        ScrollView {
            LazyVStack(spacing: skinManager.current.spacingL) {
                if let log = viewModel.log {
                    DetailTitleCard(title: detailDate(log.date), subtitle: Date(timeIntervalSince1970: Double(log.date) / 1000).formatted(.dateTime.weekday(.wide))) {
                        LolitaBadge(text: "\(viewModel.items.count) 件服饰", color: detailAccent(skinManager.current, colorScheme: colorScheme))
                        if !viewModel.imageUrls.isEmpty { LolitaBadge(text: "\(viewModel.imageUrls.count) 张照片", color: detailAccent(skinManager.current, colorScheme: colorScheme)) }
                    }
                    if !log.note.isEmpty {
                        LolitaSection(title: "穿搭笔记") { Text(log.note).font(.body).fixedSize(horizontal: false, vertical: true) }
                    }
                    if !viewModel.imageUrls.isEmpty { ImageGalleryPager(urls: viewModel.imageUrls) }
                    HStack {
                        Text("关联服饰 · \(viewModel.items.count) 件").font(.headline)
                        Spacer()
                        NavigationLink(destination: OutfitLogEditScreen(logId: logId)) { Label("管理", systemImage: "plus") }.font(.subheadline)
                    }.padding(.horizontal, 4)
                    if viewModel.items.isEmpty {
                        LolitaCard { Text("还没有关联服饰，可以从编辑页添加。").font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
                    } else {
                        ForEach(viewModel.items, id: \.id) { item in
                            OutfitDetailItemCard(item: item, brandName: viewModel.brandNames[item.brandId] ?? "", categoryName: viewModel.categoryNames[item.categoryId] ?? "") {
                                removeItem = item
                            }
                        }
                    }
                } else {
                    DetailLoadState(isLoading: viewModel.isLoading, message: viewModel.errorMessage ?? "穿搭记录已不存在") { reloadToken += 1 }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(skinManager.current.spacingL)
        }
        .lolitaNavBar(title: "穿搭详情", showBack: true)
        .task(id: reloadToken) { await viewModel.load(logId: logId) }
        .toolbar {
            #if os(iOS)
            ToolbarItemGroup(placement: .topBarTrailing) { toolbarActions }
            #else
            ToolbarItemGroup(placement: .automatic) { toolbarActions }
            #endif
        }
        .alert("移除关联服饰？", isPresented: Binding(get: { removeItem != nil }, set: { if !$0 { removeItem = nil } })) {
            Button("取消", role: .cancel) { removeItem = nil }
            Button("移除", role: .destructive) {
                guard let item = removeItem else { return }
                Task {
                    do { try await viewModel.removeItem(item.id) }
                    catch { operationError = userFacingError(error) }
                }
                removeItem = nil
            }
        } message: { Text("仅解除「\(removeItem?.name ?? "")」与这次穿搭的关联，服饰和照片会保留。") }
        .alert("删除这条穿搭？", isPresented: $showDelete) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                Task {
                    do { try await viewModel.delete(); dismiss() }
                    catch { operationError = userFacingError(error) }
                }
            }
        } message: { Text("穿搭笔记和照片记录将被删除，关联服饰会保留。") }
        .alert("操作失败", isPresented: Binding(get: { operationError != nil }, set: { if !$0 { operationError = nil } })) {
            Button("确定") { operationError = nil }
        } message: { Text(operationError ?? "") }
    }

    @ViewBuilder private var toolbarActions: some View {
        if viewModel.log != nil {
            NavigationLink(destination: OutfitLogEditScreen(logId: logId)) { Image(systemName: "pencil") }.accessibilityLabel("编辑穿搭")
            Menu {
                Button("删除穿搭", systemImage: "trash", role: .destructive) { showDelete = true }
            } label: { Image(systemName: "ellipsis") }
        }
    }
}

private struct OutfitDetailItemCard: View {
    let item: Item
    let brandName: String
    let categoryName: String
    let onRemove: () -> Void
    var body: some View {
        LolitaCard(variant: .compact) {
            HStack(spacing: 8) {
                NavigationLink(destination: ItemDetailScreen(itemId: item.id)) {
                    HStack(spacing: 12) {
                        LolitaThumbnail(path: item.imageUrls.values.first, symbol: "hanger", width: 56, height: 70)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            Text([brandName, categoryName].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            DetailStatusBadge(status: item.status)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "minus.circle").frame(width: 44, height: 44)
                }.accessibilityLabel("移除关联服饰\(item.name)")
            }
        }
    }
}
