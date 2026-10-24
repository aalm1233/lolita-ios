import SwiftUI

struct PaymentManageScreen: View {
    @AppStorage("showTotalPrice") private var showAmount = true
    @State private var operationError: String?
    @State private var confirmation: Action?
    @State private var deleting: Payment?
    @StateObject private var viewModel: PaymentManageViewModel
    private enum Action: String, Identifiable { case historical, tracked, archive, bind; var id: String { rawValue } }
    init(priceId: Int64) { _viewModel = StateObject(wrappedValue: PaymentManageViewModel(priceId: priceId)) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let error = viewModel.error { Text(error).foregroundStyle(.red) }
                else if let order = viewModel.order {
                    summary(order)
                    NavigationLink("退款与取消购买", destination: AfterSaleScreen(priceId: order.id))
                        .accessibilityIdentifier("after-sale")
                    if order.cancellation != nil {
                        Text("已取消购买，原订单及实付保留。再次购买请新建订单。").font(.caption).foregroundStyle(.secondary)
                    } else if !order.isCurrent {
                        LolitaSection(title: "历史账本") {
                            Text("这笔账本仅供查看，原计划不会计入当前待付。选择当前订单不会新增实付。")
                            Button("选择为当前订单") { confirmation = .bind }
                        }
                    } else if !order.isTracked {
                        LolitaSection(title: "购买资料核对") {
                            Text(order.price.purchaseRecordStatus == .historicalOwned ? "已保留历史拥有证据，余额未知，不发送付款提醒。" : "请核对原记录，不会用总价、下单时间补造实付。")
                            if order.price.purchaseRecordStatus != .historicalOwned {
                                Button("确认为历史已购（不补造实付）") { confirmation = .historical }
                            }
                            Button("账本已核对，启用付款跟踪") { confirmation = .tracked }
                        }
                    }
                    LolitaSection(title: "付款阶段（计划）") {
                        if order.stages.isEmpty { Text("原账本没有付款阶段。请保留历史记录，核对后可归档并建立新订单。") }
                        ForEach(order.stages) { stage in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(stage.name).font(.subheadline.weight(.semibold))
                                Text("计划 \(money(stage.amount))").font(.subheadline)
                                Text(stage.dueDate.map { "应付日 · \(detailDate($0))" } ?? "应付日期待定").font(.caption).foregroundStyle(.secondary)
                                if let remaining = order.stageRemaining[stage.id] { Text("剩余 \(money(remaining))").font(.caption).foregroundStyle(.secondary) }
                            }.padding(.vertical, 5)
                        }
                        if order.isTracked { NavigationLink("编辑付款计划", destination: PriceEditScreen(itemId: order.price.itemId, priceId: order.id)) }
                    }
                    LolitaSection(title: "真实付款") {
                        if order.payments.filter(\.isPaid).isEmpty { Text("尚未录入真实付款").foregroundStyle(.secondary) }
                        ForEach(order.payments.filter(\.isPaid), id: \.id) { payment in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(money(payment.amount)).font(.headline).monospacedDigit()
                                Text(payment.paidDate.map { detailDate($0) } ?? "真实付款日期未知").font(.caption).foregroundStyle(.secondary)
                                if order.isCurrent && order.price.purchaseRecordStatus != .needsReview {
                                    HStack {
                                        NavigationLink("更正", destination: PaymentEditScreen(priceId: order.id, paymentId: payment.id))
                                        Spacer()
                                        Button("删除误记", role: .destructive) { deleting = payment }
                                    }.font(.caption)
                                }
                            }.padding(.vertical, 6)
                        }
                        if order.isCurrent && order.price.purchaseRecordStatus != .needsReview {
                            NavigationLink("记录真实付款", destination: PaymentEditScreen(priceId: order.id))
                        }
                    }
                    let legacy = order.payments.filter { !$0.isPaid }
                    if !legacy.isEmpty {
                        LolitaSection(title: "原始记录保留") {
                            DisclosureGroup("\(legacy.count) 条旧计划（不重复计入待付）") {
                                ForEach(legacy, id: \.id) { record in
                                    Text("\(money(record.amount)) · 原到期日 \(detailDate(record.dueDate))").font(.caption).padding(.vertical, 4)
                                }
                            }
                        }
                    }
                    if order.isCurrent { Button("归档当前订单", role: .destructive) { confirmation = .archive } }
                } else { ProgressView("正在读取账本…") }
            }.padding(16)
        }
        .disabled(viewModel.isWorking)
        .lolitaNavBar(title: "订单与账本", showBack: true)
        .task { await viewModel.observe() }
        .alert("操作失败", isPresented: Binding(get: { operationError != nil }, set: { if !$0 { operationError = nil } })) {
            Button("确定") { operationError = nil }
        } message: { Text(operationError ?? "") }
        .confirmationDialog(confirmationText, isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })) {
            Button("确认") {
                let action = confirmation; confirmation = nil
                perform {
                    switch action {
                    case .bind: try await viewModel.bind()
                    case .historical: try await viewModel.confirm(historical: true)
                    case .tracked: try await viewModel.confirm(historical: false)
                    case .archive: try await viewModel.archive()
                    case nil: break
                    }
                }
            }
        }
        .confirmationDialog("删除这条误记实付？原订单和计划会保留，余额将重新计算。", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("删除误记", role: .destructive) { if let deleting { perform { try await viewModel.delete(deleting) } }; deleting = nil }
        }
    }

    private var confirmationText: String {
        switch confirmation {
        case .bind: "选择这笔为当前订单？原账本保留，未核对的购买资料仍需确认。"
        case .historical: "确认历史上已经拥有？不会补造付款金额或日期，余额保持未知。"
        case .tracked: "确认真实付款已全部录入、计划合计正确且余额与实际一致？启用后会按计划跟踪待付和提醒。"
        case .archive: "归档后停止这笔计划的待付与提醒，保留全部账本和物品状态。归档不代表取消购买或退款。"
        case nil: "确认操作"
        }
    }
    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        viewModel.isWorking = true
        Task {
            defer { viewModel.isWorking = false }
            do { try await action() } catch { operationError = userFacingError(error) }
        }
    }
    private func summary(_ order: OrderSnapshot) -> some View {
        OrderLedgerSummary(order: order, showAmount: showAmount)
    }
    private func money(_ value: Double) -> String { showAmount ? detailMoney(value) : "金额已隐藏" }
}

/// Shared by the real order screen and source-rendered layout checks.
struct OrderLedgerSummary: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let order: OrderSnapshot
    var showAmount = true
    private func money(_ value: Double) -> String { showAmount ? detailMoney(value) : "金额已隐藏" }
    var body: some View {
        LolitaSection(title: order.isCurrent ? "当前订单" : "历史订单") {
            amountRow("订单应付（含邮费）", value: money(order.price.totalPrice))
            amountRow("其中邮费", value: money(order.price.shipping))
            amountRow("已录实付", value: money(order.paidAmount))
            amountRow("已到账退款", value: money(order.refundedAmount))
            amountRow("净支出", value: money(order.netAmount))
            amountRow("未付余额", value: order.remainingAmount.map(money) ?? "待核对")
        }
    }
    @ViewBuilder private func amountRow(_ label: String, value: String) -> some View {
        let amount = Text(value).foregroundStyle(.secondary)
            .lineLimit(1).minimumScaleFactor(0.7)
            .accessibilityIdentifier("order-value-\(label)")
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                Text(label).fixedSize(horizontal: false, vertical: true)
                amount
            }.frame(maxWidth: .infinity, alignment: .leading)
        } else {
            LabeledContent(label) { amount }
        }
    }
}
