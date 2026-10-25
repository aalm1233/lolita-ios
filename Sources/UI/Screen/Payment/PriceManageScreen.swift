import SwiftUI

struct PriceManageScreen: View {
    @AppStorage("showTotalPrice") private var showAmount = true
    @StateObject private var viewModel: PriceManageViewModel
    init(itemId: Int64) { _viewModel = StateObject(wrappedValue: PriceManageViewModel(itemId: itemId)) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if viewModel.isLoading { ProgressView("正在读取订单…") }
                if let error = viewModel.error { Text(error).foregroundStyle(.red) }
                if viewModel.isShared {
                    LolitaSection(title: "共用主件订单") {
                        Text("这件小物的价格已包含在主件中，付款在主件记一次。")
                        NavigationLink("查看主件", destination: ItemDetailScreen(itemId: viewModel.ownerId))
                    }
                }
                if let current = viewModel.orders.first(where: \.isCurrent) {
                    LolitaSection(title: "当前订单") { orderLink(current) }
                } else if !viewModel.isLoading, viewModel.error == nil {
                    LolitaSection(title: "当前订单") {
                        Text(viewModel.orders.isEmpty ? "尚未建立购买订单。" : "请选择原账本中的当前订单，或明确建立一笔新购买。")
                            .foregroundStyle(.secondary)
                        NavigationLink("建立购买订单", destination: PriceEditScreen(itemId: viewModel.ownerId))
                    }
                }
                let historical = viewModel.orders.filter { !$0.isCurrent }
                if !historical.isEmpty {
                    LolitaSection(title: "原账本与历史订单") {
                        Text("历史金额和付款保留；未选为当前的计划不计入待付，也不发送提醒。")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(historical) { order in orderLink(order) }
                    }
                }
            }.padding(16)
        }
        .lolitaNavBar(title: "购买订单", showBack: true)
        .task { await viewModel.observe() }
    }

    private func orderLink(_ order: OrderSnapshot) -> some View {
        NavigationLink { PaymentManageScreen(priceId: order.id) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(order.price.type.displayName).font(.headline)
                    Spacer()
                    SkinIcon(systemName: "chevron.right").foregroundStyle(.secondary)
                }
                Text(money(order.price.totalPrice)).font(.title3).monospacedDigit()
                Text("已录实付 \(money(order.paidAmount))").font(.subheadline)
                Text(order.cancellation != nil ? "已取消购买 · 原账本保留" : order.isTracked ? "待付 \(money(order.remainingAmount ?? 0))" : order.price.purchaseRecordStatus == .historicalOwned ? "历史已购 · 付款资料可能不完整" : "购买关系待核对")
                    .font(.caption).foregroundStyle(.secondary)
            }.foregroundStyle(.primary).padding(.vertical, 8)
        }
        .accessibilityIdentifier("order-\(order.id)")
    }
    private func money(_ value: Double) -> String { showAmount ? detailMoney(value) : "金额已隐藏" }
}
