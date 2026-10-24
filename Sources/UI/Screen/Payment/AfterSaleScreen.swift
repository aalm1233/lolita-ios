import SwiftUI

struct FinanceValueRow: View {
    @AppStorage("showTotalPrice") private var showAmount = true
    @Environment(\.dynamicTypeSize) private var typeSize
    let title: String
    let amount: Double?
    private var value: some View {
        Text(showAmount ? amount.map(detailMoney) ?? "待确认" : "金额已隐藏")
            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            .foregroundStyle(.secondary).accessibilityIdentifier("finance-value-\(title)")
    }
    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) { Text(title); value }.frame(maxWidth: .infinity, alignment: .leading)
        } else { LabeledContent(title) { value } }
    }
}

struct AfterSaleScreen: View {
    let priceId: Int64
    @AppStorage("showTotalPrice") private var showAmount = true
    @State private var order: OrderSnapshot?
    @State private var error: String?
    @State private var voiding: OrderRefund?
    @State private var voidFingerprint = ""
    @State private var working = false
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let order {
                    LolitaSection(title: order.cancellation == nil ? "售后账目" : "已取消购买") {
                        FinanceValueRow(title: "原实付", amount: order.paidAmount)
                        FinanceValueRow(title: "已到账退款", amount: order.refundedAmount)
                        FinanceValueRow(title: "净支出", amount: order.netAmount)
                        Text("退款保留原实付，不增加未付计划。约定退款不代表已经到账。")
                            .font(.caption).foregroundStyle(.secondary)
                        if order.netAmount > 0 {
                            NavigationLink("记录到账退款 / 退差价", destination: FinanceEditorScreen(mode: .refund(priceId)))
                                .accessibilityIdentifier("record-refund")
                        }
                    }
                    if let cancellation = order.cancellation {
                        LolitaSection(title: "退款约定") {
                            FinanceValueRow(title: "约定退款总额", amount: cancellation.expectedRefundTotal)
                            FinanceValueRow(title: "尚待到账", amount: order.pendingRefund)
                            Text("取消后不能续付或重新绑定，重新购买请建立新订单。")
                                .font(.caption).foregroundStyle(.secondary)
                            if showAmount && !cancellation.note.isEmpty { Text(cancellation.note).font(.caption) }
                            NavigationLink("调整退款约定", destination: FinanceEditorScreen(mode: .cancel(priceId)))
                        }
                    } else if order.isTracked {
                        NavigationLink("取消整笔购买", destination: FinanceEditorScreen(mode: .cancel(priceId)))
                            .foregroundStyle(.red).accessibilityIdentifier("cancel-purchase")
                    }
                    LolitaSection(title: "到账与撤销记录") {
                        if order.refunds.isEmpty { Text("尚无到账退款").foregroundStyle(.secondary) }
                        ForEach(order.refunds) { refund in
                            VStack(alignment: .leading, spacing: 8) {
                                FinanceValueRow(title: refund.kind.title, amount: refund.amount)
                                Text(detailDate(refund.receivedAt)).font(.caption).foregroundStyle(.secondary)
                                if showAmount && !refund.note.isEmpty { Text(refund.note).font(.caption) }
                                if refund.voidedAt != nil { Text("已撤销误记，原记录保留").font(.caption).foregroundStyle(.secondary) }
                                else {
                                    Button("撤销误记", role: .destructive) { voidFingerprint = order.fingerprint; voiding = refund }
                                }
                            }.padding(.vertical, 6)
                        }
                    }
                } else if error == nil { ProgressView("正在读取售后账目…") }
                if let error { Text(error).foregroundStyle(.red) }
            }.padding(16).padding(.bottom, 80)
        }
        .lolitaNavBar(title: "退款与取消购买", showBack: true)
        .disabled(working)
        .task {
            do {
                let first = try await AppModule.shared.orderRepository.get(priceId)
                order = first
                for await values in AppModule.shared.orderRepository.observe(itemId: first.price.itemId) {
                    guard !Task.isCancelled else { return }; order = values.first { $0.id == priceId }
                }
            } catch { self.error = userFacingError(error) }
        }
        .confirmationDialog("撤销这条误记退款？原记录会保留，净支出将重新计算。", isPresented: Binding(get: { voiding != nil }, set: { if !$0 { voiding = nil } })) {
            Button("确认撤销", role: .destructive) {
                guard let value = voiding else { return }
                let expected = voidFingerprint; voiding = nil; working = true
                Task {
                    defer { working = false }
                    do { try await AppModule.shared.afterSaleRepository.voidRefund(value.id, expected: expected) }
                    catch { self.error = userFacingError(error) }
                }
            }
        }
    }
}

enum FinanceEditorMode: Hashable {
    case reference(Int64), refund(Int64), cancel(Int64), budget(String)
    var key: String {
        switch self {
        case .reference(let id): "reference-\(id)"
        case .refund(let id): "refund-\(id)"
        case .cancel(let id): "cancel-\(id)"
        case .budget(let month): "budget-\(month)"
        }
    }
    var title: String {
        switch self {
        case .reference: "独立参考价"
        case .refund: "记录到账退款"
        case .cancel: "取消购买与退款约定"
        case .budget: "设置月预算"
        }
    }
}
struct FinanceDraft: Codable, Equatable {
    var amount = ""
    var note = ""
    var kind = RefundKind.refund
    var receivedDate = Date()
    var unknownExpected = true
    var confirmed = false
    var operationId = UUID().uuidString
    var fingerprint = ""
    var reference: ItemReferencePrice?
    var budget: MonthlyBudget?
    var input: [String] { [amount, note, kind.rawValue, String(receivedDate.timeIntervalSince1970), String(unknownExpected), String(confirmed)] }
}

@MainActor
final class FinanceEditorViewModel: ObservableObject {
    @Published var draft = FinanceDraft()
    @Published private(set) var loaded = false
    @Published private(set) var loadError: String?
    @Published private(set) var saving = false
    @Published private(set) var order: OrderSnapshot?
    let mode: FinanceEditorMode
    private var baseline: [String] = []
    private var restored = false
    private let afterSale: AfterSaleRepository
    private let orders: OrderRepository
    private let finance: FinanceRepository
    private let defaults: UserDefaults
    var draftKey: String { "lolita.finance.draft." + mode.key }
    var hasChanges: Bool { restored || (loaded && draft.input != baseline) }
    init(mode: FinanceEditorMode, afterSale: AfterSaleRepository = AppModule.shared.afterSaleRepository,
         orders: OrderRepository = AppModule.shared.orderRepository, finance: FinanceRepository = AppModule.shared.financeRepository,
         defaults: UserDefaults = .standard) {
        self.mode = mode; self.afterSale = afterSale; self.orders = orders; self.finance = finance; self.defaults = defaults
    }
    func load() async {
        guard !loaded, loadError == nil else { return }
        do {
            switch mode {
            case .reference(let id):
                draft.reference = try await afterSale.reference(itemId: id)
                if let reference = draft.reference { draft.amount = String(format: "%.2f", reference.amount); draft.note = reference.note }
            case .refund(let id), .cancel(let id):
                let order = try await orders.get(id); self.order = order; draft.fingerprint = order.fingerprint
                if case .cancel = mode, let cancellation = order.cancellation {
                    draft.unknownExpected = cancellation.expectedRefundTotal == nil
                    draft.amount = cancellation.expectedRefundTotal.map { String(format: "%.2f", $0) } ?? ""
                    draft.note = cancellation.note
                }
            case .budget(let month):
                draft.budget = try await finance.get().budgets.first { $0.month == month }
                draft.amount = draft.budget.map { String(format: "%.2f", Double($0.amountCents) / 100) } ?? ""
            }
            baseline = draft.input
            if let data = defaults.data(forKey: draftKey), let saved = try? JSONDecoder().decode(FinanceDraft.self, from: data) {
                draft = saved; restored = true
            }
            loaded = true
        } catch { loadError = userFacingError(error) }
    }
    func persist() {
        guard hasChanges, !saving, let data = try? JSONEncoder().encode(draft) else { return }
        defaults.set(data, forKey: draftKey)
    }
    func discard() { restored = false; baseline = draft.input; defaults.removeObject(forKey: draftKey) }
    func save() async throws {
        guard loaded, loadError == nil, !saving else { throw ValidationError.invalid(loadError ?? "资料尚未准备好，请稍候") }
        // Capture every editable input and operation identity before suspension.
        let submitted = draft
        saving = true; defer { saving = false }
        switch mode {
        case .reference(let id):
            try await afterSale.saveReference(itemId: id, amount: InputValidation.amount(submitted.amount, label: "参考价"), note: submitted.note, expected: submitted.reference)
        case .refund(let id):
            let amount = try InputValidation.amount(submitted.amount, label: "到账金额")
            _ = try await afterSale.recordRefund(OrderRefund(priceId: id, amount: amount, kind: submitted.kind,
                receivedAt: Int64(submitted.receivedDate.timeIntervalSince1970 * 1000), note: submitted.note, operationId: submitted.operationId), expected: submitted.fingerprint)
        case .cancel(let id):
            let expected = submitted.unknownExpected ? nil : try InputValidation.amount(submitted.amount, label: "约定退款总额")
            try await afterSale.cancelOrder(priceId: id, expectedRefund: expected, note: submitted.note, expected: submitted.fingerprint, confirmed: submitted.confirmed)
        case .budget(let month):
            try await finance.saveBudget(month: month, amount: InputValidation.amount(submitted.amount, label: "月预算"), expected: submitted.budget)
        }
        discard()
    }
    func removeReference() async throws {
        guard case .reference(let id) = mode, let reference = draft.reference, !saving else { return }
        saving = true; defer { saving = false }
        try await afterSale.removeReference(itemId: id, expected: reference); discard()
    }
}

struct FinanceEditorScreen: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("showTotalPrice") private var showAmount = true
    @StateObject private var model: FinanceEditorViewModel
    @State private var error: String?
    @State private var discard = false
    @State private var deleteReference = false
    init(mode: FinanceEditorMode) { _model = StateObject(wrappedValue: FinanceEditorViewModel(mode: mode)) }
    var body: some View {
        Form {
            if let error = model.loadError { Text(error).foregroundStyle(.red) }
            if !showAmount { Text("主动编辑时显示金额，离开后按隐私设置隐藏。").font(.caption).foregroundStyle(.secondary) }
            Section {
                switch model.mode {
                case .reference:
                    Text("仅记录参考，不建立订单、付款或提醒，也不改变物品状态。").font(.caption).foregroundStyle(.secondary)
                    amountField("参考金额")
                case .refund:
                    Text("只登记真实到账，不会向商家发起退款。").font(.caption).foregroundStyle(.secondary)
                    Picker("到账类型", selection: $model.draft.kind) { ForEach(RefundKind.allCases, id: \.self) { Text($0.title).tag($0) } }.accessibilityIdentifier("refund-kind")
                    amountField("到账金额")
                    DatePicker("实际到账日期", selection: $model.draft.receivedDate, in: ...Date(), displayedComponents: .date)
                case .cancel:
                    Text(model.order?.cancellation == nil ? "取消整笔当前购买：主件及共价小物回到心愿，停止待付提醒，保留照片、位置、原订单及实付。再次购买需新建订单。" : "仅调整这笔已取消订单的退款约定，不改变后续的新购买。").font(.caption).foregroundStyle(.secondary)
                    Toggle("约定退款金额待确认", isOn: $model.draft.unknownExpected)
                    if !model.draft.unknownExpected { amountField("约定退款总额") }
                    Text("约定为累计应退总额，不是已到账金额；零元表示不退，待确认不等于零元。").font(.caption).foregroundStyle(.secondary)
                    Toggle(model.order?.cancellation == nil ? "确认整笔取消及物品回到心愿" : "确认调整退款约定", isOn: $model.draft.confirmed)
                case .budget(let month):
                    Text(month + " 月预算").font(.headline)
                    amountField("预算金额")
                    Text("预计可用＝预算－本月净支出－本月待付－以前月份未付。未知日期单列。").font(.caption).foregroundStyle(.secondary)
                }
                TextField("备注（最多500字）", text: $model.draft.note, axis: .vertical).lineLimit(2...5)
            }
            if case .reference = model.mode, model.draft.reference != nil {
                Button("删除独立参考价", role: .destructive) { deleteReference = true }
            }
        }
        .disabled(!model.loaded || model.saving)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            LolitaEditorSaveBar(title: model.saving ? "保存中…" : "保存",
                                enabled: model.loaded && !model.saving && model.loadError == nil, identifier: "finance-save") {
                Task { do { try await model.save(); dismiss() } catch { self.error = userFacingError(error) } }
            }
        }
        .lolitaNavBar(title: model.mode.title, showBack: true, onBack: { if model.hasChanges { discard = true } else { dismiss() } })
        .interactiveDismissDisabled(model.hasChanges || model.saving)
        .task { await model.load() }
        .onChange(of: model.draft) { _, _ in model.persist() }
        .onDisappear { model.persist() }
        .alert("保存失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("确定", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
        .confirmationDialog("放弃未保存的输入？", isPresented: $discard) {
            Button("放弃修改", role: .destructive) { model.discard(); dismiss() }
        }
        .confirmationDialog("删除参考价？原订单和付款不受影响。", isPresented: $deleteReference) {
            Button("确认删除", role: .destructive) {
                Task { do { try await model.removeReference(); dismiss() } catch { self.error = userFacingError(error) } }
            }
        }
    }
    private func amountField(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(title, text: $model.draft.amount)
            #if os(iOS)
                .keyboardType(.decimalPad)
            #endif
        }
    }
}
