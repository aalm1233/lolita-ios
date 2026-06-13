import SwiftUI

struct PriceManageScreen: View {
    @EnvironmentObject var skinManager: SkinManager
    @StateObject private var viewModel: PriceManageViewModel

    init(itemId: Int64) {
        _viewModel = StateObject(wrappedValue: PriceManageViewModel(itemId: itemId))
    }

    var body: some View {
        Group {
            if viewModel.prices.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "yensign.circle")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("暂无价格记录")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            } else {
                List {
                    ForEach(viewModel.prices, id: \.id) { price in
                        NavigationLink(destination: PaymentManageScreen(priceId: price.id)) {
                            PriceRow(price: price)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task {
                                    try? await viewModel.delete(price)
                                }
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
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
        .task { await viewModel.load() }
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
                if price.type == .depositBalance {
                    HStack(spacing: 8) {
                        if let d = price.deposit { Text("定金 ¥\(String(format: "%.2f", d))") }
                        if let b = price.balance { Text("尾款 ¥\(String(format: "%.2f", b))") }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
