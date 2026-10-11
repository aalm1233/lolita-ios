import SwiftUI

struct PaymentManageScreen: View {
    @State private var deleteError: String?
    @EnvironmentObject var skinManager: SkinManager
    @StateObject private var viewModel: PaymentManageViewModel

    init(priceId: Int64) {
        _viewModel = StateObject(wrappedValue: PaymentManageViewModel(priceId: priceId))
    }

    var body: some View {
        VStack(spacing: 0) {
            summaryHeader
            if viewModel.payments.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "creditcard")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("暂无付款记录")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                List {
                    ForEach(viewModel.payments, id: \.id) { payment in
                        NavigationLink(destination: PaymentEditScreen(priceId: viewModel.priceId, paymentId: payment.id)) {
                            PaymentRow(payment: payment)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task { do { try await viewModel.delete(payment) } catch { deleteError = userFacingError(error) } }
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
        .lolitaNavBar(title: "付款管理", showBack: true)
#if os(iOS)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    if let price = viewModel.price {
                        NavigationLink(destination: PriceEditScreen(itemId: price.itemId, priceId: price.id)) { Image(systemName: "pencil") }
                    }
                    NavigationLink(destination: PaymentEditScreen(priceId: viewModel.priceId)) { Image(systemName: "plus") }
                }
            }
        }
#endif
        .onAppear { Task { await viewModel.load() }; viewModel.observe() }
        .onDisappear { viewModel.stopObserving() }
    }

    private var summaryHeader: some View {
        HStack(spacing: 16) {
            summaryItem("总计", viewModel.totalAmount, .primary)
            summaryItem("已付", viewModel.paidAmount, .green)
            summaryItem("待付", viewModel.remainingAmount, .orange)
        }
        .padding()
        .background(skinManager.current.backgroundColor.opacity(0.5))
    }

    private func summaryItem(_ label: String, _ amount: Double, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(String(format: "¥%.2f", amount))
                .font(.headline.weight(.bold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PaymentRow: View {
    let payment: Payment

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: "¥%.2f", payment.amount))
                    .font(.subheadline.weight(.medium))
                Text(Date(timeIntervalSince1970: TimeInterval(payment.dueDate) / 1000), style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if payment.isPaid {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                if payment.dueDate < Int64(Date().timeIntervalSince1970 * 1000) {
                    Text("逾期")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                } else {
                    Text("待付")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
