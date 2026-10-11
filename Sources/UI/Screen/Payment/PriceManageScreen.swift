import SwiftUI

struct PriceManageScreen: View {
    @State private var deleteError: String?
    @EnvironmentObject var skinManager: SkinManager
    @StateObject private var viewModel: PriceManageViewModel

    init(itemId: Int64) {
        _viewModel = StateObject(wrappedValue: PriceManageViewModel(itemId: itemId))
    }

    var body: some View {
        Group {
            if viewModel.prices.isEmpty {
                LolitaEmptyState(title: "暂无价格记录", message: "点击右上角 + 添加全款或定金与尾款。", systemImage: "yensign.circle")
            } else {
                List {
                    ForEach(viewModel.prices, id: \.id) { price in
                        NavigationLink(destination: PaymentManageScreen(priceId: price.id)) {
                            PriceRow(price: price)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task {
                                    do { try await viewModel.delete(price) } catch { deleteError = userFacingError(error) }
                                }
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .alert("删除失败", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("确定") { deleteError = nil }
        } message: { Text(deleteError ?? "") }
        .lolitaNavBar(title: "价格管理", showBack: true)
#if os(iOS)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(destination: PriceEditScreen(itemId: viewModel.itemId)) {
                    Image(systemName: "plus")
                }
            }
        }
#endif
        .onAppear { Task { await viewModel.load() } }
    }
}

private struct PriceRow: View {
    let price: Price

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(price.type == .full ? "全款" : "定金+尾款")
                    .font(.subheadline.weight(.medium))
                Text(String(format: "¥%.2f", price.totalPrice))
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                if price.type == .depositBalance {
                    VStack(alignment: .leading, spacing: 4) {
                        if let d = price.deposit { Text("定金 ¥\(String(format: "%.2f", d))") }
                        if let b = price.balance { Text("尾款 ¥\(String(format: "%.2f", b))") }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
}
