import SwiftUI

struct PaymentManageScreen: View {
    @State private var operationError: String?
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
                                Task { do { try await viewModel.delete(payment) } catch { operationError = userFacingError(error) } }
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            if !payment.isPaid {
                                Button {
                                    Task {
                                        do { try await AppModule.shared.paymentRepository.markPaid(payment.id) }
                                        catch { operationError = userFacingError(error) }
                                    }
                                } label: { Label("标记已付", systemImage: "checkmark.circle") }
                                    .tint(.green)
                            }
                        }
                    }
                }
            }
        }
        .alert("操作失败", isPresented: Binding(get: { operationError != nil }, set: { if !$0 { operationError = nil } })) {
            Button("确定") { operationError = nil }
        } message: { Text(operationError ?? "") }
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
            if payment.reminderSet && !payment.isPaid {
                Image(systemName: "bell.fill").font(.caption).foregroundStyle(.secondary)
                    .accessibilityLabel("提前 \(payment.customReminderDays ?? 1) 天提醒")
            }
        }
        .padding(.vertical, 4)
    }
}
