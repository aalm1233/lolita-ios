import SwiftUI

struct PaymentStageInput: Identifiable, Equatable {
    let id = UUID()
    var storedId: Int64 = 0
    var name = ""
    var amountText = ""
    var hasDueDate = false
    var dueDate = Date()
    var reminderSet = false
    var reminderDays = 1

    init() {}
    init(_ stage: PaymentStage) {
        storedId = stage.id; name = stage.name; amountText = String(format: "%.2f", stage.amount)
        hasDueDate = stage.dueDate != nil
        if let date = stage.dueDate { dueDate = Date(timeIntervalSince1970: Double(date) / 1000) }
        reminderSet = stage.reminderSet; reminderDays = stage.customReminderDays ?? 1
    }
}

@MainActor
final class PriceEditViewModel: ObservableObject {
    @Published private(set) var reference: ItemReferencePrice?
    @Published var type: PriceType = .full
    @Published var totalPriceText = ""
    @Published var depositText = ""
    @Published var balanceText = ""
    @Published var shippingText = "0"
    @Published var initialPaid = false
    @Published var paymentDate = Date()
    @Published var isSaving = false
    @Published var stages: [PaymentStageInput] = [PaymentStageInput()]
    @Published private(set) var loadError: String?
    @Published private(set) var isLoaded = false
    private var baseline: [String]?
    private var fingerprint: String?
    private let repo: PriceRepository
    let itemId: Int64
    private(set) var priceId: Int64?

    private var state: [String] {
        [type.rawValue, totalPriceText, depositText, balanceText, shippingText, String(initialPaid), String(paymentDate.timeIntervalSince1970)]
        + stages.map { "\($0.name)|\($0.amountText)|\($0.hasDueDate)|\($0.dueDate.timeIntervalSince1970)|\($0.reminderSet)|\($0.reminderDays)" }
    }
    var hasChanges: Bool { baseline.map { $0 != state } ?? false }

    init(itemId: Int64, priceId: Int64? = nil, repository: PriceRepository = AppModule.shared.priceRepository) {
        self.itemId = itemId; self.priceId = priceId; repo = repository
    }

    func load() async {
        guard !isLoaded else { return }
        guard let priceId else {
            do { reference = try await repo.reference(itemId: itemId); isLoaded = true; baseline = state }
            catch { loadError = userFacingError(error) }
            return
        }
        do {
            let order = try await repo.orderSnapshot(priceId)
            guard order.isTracked else { throw ValidationError.invalid("请先核对历史账本并启用付款跟踪") }
            let price = order.price
            type = price.type; totalPriceText = String(format: "%.2f", price.totalPrice)
            depositText = price.deposit.map { String(format: "%.2f", $0) } ?? ""
            balanceText = price.balance.map { String(format: "%.2f", $0) } ?? ""
            shippingText = String(format: "%.2f", price.shipping)
            stages = order.stages.map(PaymentStageInput.init)
            // Old FULL/DEPOSIT_BALANCE rows can contain several independently dated
            // payments. Show their existing plan rather than multiplying the total.
            if (type == .full && stages.count != 1) || (type == .depositBalance && stages.count != 2) {
                type = .multiStage
            }
            fingerprint = order.fingerprint; isLoaded = true; baseline = state
        } catch { loadError = userFacingError(error) }
    }

    func adoptReference() {
        guard priceId == nil, let reference, !isSaving else { return }
        changeType(.full); totalPriceText = String(format: "%.2f", reference.amount)
    }

    func changeType(_ type: PriceType) {
        self.type = type
        let count = type == .depositBalance ? 2 : type == .full ? 1 : max(1, stages.count)
        while stages.count < count { stages.append(PaymentStageInput()) }
        if type != .multiStage { stages = Array(stages.prefix(count)) }
    }

    func save() async throws {
        guard !isSaving else { throw ValidationError.invalid("正在保存，请稍候") }
        if let loadError { throw ValidationError.invalid(loadError) }
        isSaving = true; defer { isSaving = false }
        // Freeze all input before the first await.
        let submittedType = type
        let shipping = try InputValidation.amount(shippingText, label: "邮费")
        let deposit = submittedType == .depositBalance ? try InputValidation.amount(depositText, label: "定金") : nil
        let balance = submittedType == .depositBalance ? try InputValidation.amount(balanceText, label: "尾款") : nil
        let total = submittedType == .depositBalance ? try OrderAccounting.sum([deposit ?? 0, balance ?? 0])
            : try InputValidation.amount(totalPriceText, label: "应付总额")
        let submittedPaidDate = initialPaid ? Int64(paymentDate.timeIntervalSince1970 * 1000) : nil
        var plan: [PaymentStage] = []
        for (index, input) in stages.enumerated() {
            let amount = submittedType == .full ? total : submittedType == .depositBalance ? (index == 0 ? deposit ?? 0 : balance ?? 0)
                : try InputValidation.amount(input.amountText, label: "阶段金额")
            guard amount > 0 else { continue }
            let name = submittedType == .full ? "全款" : submittedType == .depositBalance ? (index == 0 ? "定金" : "尾款") : try InputValidation.name(input.name)
            plan.append(PaymentStage(id: input.storedId, priceId: priceId ?? 0, name: name, amount: amount,
                dueDate: input.hasDueDate ? Int64(input.dueDate.timeIntervalSince1970 * 1000) : nil,
                reminderSet: input.hasDueDate && input.reminderSet, customReminderDays: input.reminderSet ? input.reminderDays : nil))
        }
        let value = Price(id: priceId ?? 0, itemId: itemId, type: submittedType, totalPrice: total,
                          deposit: deposit, balance: balance, shipping: shipping)
        let saved = try await repo.saveWithPayments(value, initialPaidDate: submittedPaidDate, stages: plan, expected: fingerprint)
        priceId = saved.id; baseline = state
    }
}
