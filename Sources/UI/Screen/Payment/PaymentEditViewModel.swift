import SwiftUI

@MainActor
final class PaymentEditViewModel: ObservableObject {
    @Published var amountText: String = ""
    @Published var dueDate: Date = Date()
    @Published var isPaid: Bool = false
    @Published var paidDate: Date = Date()
    @Published var isSaving: Bool = false
    @Published var reminderSet = false
    @Published var reminderDaysText = "1"
    @Published private(set) var reminderWarning: String?
    @Published private(set) var loadError: String?

    @Published private(set) var isOrderPayment = false
    @Published private(set) var allowsUnknownDate = false
    @Published var unknownPaidDate = false
    @Published var stageId: Int64?
    @Published private(set) var stages: [PaymentStage] = []
    @Published private(set) var isLoaded = false
    private var original: Payment?
    private var fingerprint: String?
    private let operationId = UUID().uuidString
    private var baseline: [String]?
    private var formState: [String] { [amountText, String(dueDate.timeIntervalSince1970), String(isPaid), String(paidDate.timeIntervalSince1970), String(reminderSet), reminderDaysText, String(unknownPaidDate), String(stageId ?? 0)] }
    var hasChanges: Bool { baseline.map { $0 != formState } ?? false }
    private let repo: PaymentRepository
    private let reminderService: PaymentReminderService?
    let priceId: Int64
    private(set) var paymentId: Int64?

    init(priceId: Int64, paymentId: Int64? = nil, repository: PaymentRepository? = nil,
         reminderService: PaymentReminderService? = nil) {
        self.priceId = priceId
        self.paymentId = paymentId
        self.repo = repository ?? AppModule.shared.paymentRepository
        self.reminderService = reminderService ?? (repository == nil ? AppModule.shared.paymentReminderService : nil)
    }

    func load() async {
        guard !isLoaded else { return }
        do {
            let snapshot = try await repo.orderSnapshot(priceId)
            isOrderPayment = snapshot.isCurrent
            stages = snapshot.stages
            if isOrderPayment {
                guard snapshot.binding?.purchaseRecordStatus != .needsReview else { throw ValidationError.invalid("请先核对历史购买资料") }
                fingerprint = snapshot.fingerprint
                allowsUnknownDate = snapshot.binding?.purchaseRecordStatus == .historicalOwned
                isPaid = true
            } else if !snapshot.stages.isEmpty || snapshot.price.purchaseRecordStatus != .needsReview {
                throw ValidationError.invalid("历史账本只供查看，请先选择当前订单")
            }
        } catch { loadError = userFacingError(error); return }
        guard let paymentId else { isLoaded = true; baseline = formState; return }
        let payment: Payment
        do {
            guard let stored = try await repo.getById(paymentId) else {
                loadError = "付款记录已被删除，请返回刷新后重试"
                return
            }
            payment = stored
        } catch { loadError = userFacingError(error); return }
        original = payment
        stageId = payment.stageId
        if payment.id < 0 || (isOrderPayment && !payment.isPaid && payment.stageId != nil) {
            original = nil
            self.paymentId = nil
            isPaid = true
            isLoaded = true; baseline = formState
            return
        }
        amountText = String(format: "%.2f", payment.amount)
        dueDate = Date(timeIntervalSince1970: TimeInterval(payment.dueDate) / 1000)
        isPaid = payment.isPaid
        reminderSet = payment.reminderSet
        reminderDaysText = String(payment.customReminderDays ?? 1)
        unknownPaidDate = payment.isPaid && payment.paidDate == nil
        allowsUnknownDate = allowsUnknownDate || unknownPaidDate
        if let pd = payment.paidDate {
            paidDate = Date(timeIntervalSince1970: TimeInterval(pd) / 1000)
        }
        isLoaded = true; baseline = formState
    }

    func requestReminderPermission() async {
        guard reminderSet, !isPaid else { return }
        reminderWarning = await reminderService?.requestNotificationAuthorization()
    }

    /// Save the submitted snapshot before any suspension; denied system access never
    /// rolls back the payment or makes the editor claim that persistence failed.
    func save() async throws -> String? {
        if let loadError { throw ValidationError.invalid(loadError) }
        guard !isSaving else { throw ValidationError.invalid("正在保存，请稍候") }
        isSaving = true
        defer { isSaving = false }

        let amount = try InputValidation.amount(amountText, label: "付款金额")
        let dueMs = Int64(dueDate.timeIntervalSince1970 * 1000)
        let submittedPaid = isPaid
        let submittedReminder = reminderSet
        let paidMs = submittedPaid && !unknownPaidDate ? Int64(paidDate.timeIntervalSince1970 * 1000) : nil
        let submittedStage = stageId
        let days: Int?
        if submittedReminder {
            guard let value = Int(reminderDaysText.trimmingCharacters(in: .whitespacesAndNewlines)),
                  (0...365).contains(value) else {
                throw ValidationError.invalid("提前天数请输入 0 到 365 的整数")
            }
            days = value
        } else { days = nil }

        if isOrderPayment {
            var payment = original.flatMap { $0.id > 0 ? $0 : nil } ?? Payment(priceId: priceId, amount: amount, dueDate: paidMs ?? 0, isPaid: true)
            payment.amount = amount; payment.isPaid = true; payment.paidDate = paidMs
            if payment.id == 0 { payment.dueDate = paidMs ?? 0 }
            payment.stageId = submittedStage
            payment.operationId = payment.operationId ?? operationId
            paymentId = try await repo.saveActual(payment, expected: fingerprint).id
        } else if let paymentId {
            guard var payment = try await repo.getById(paymentId) else {
                throw ValidationError.invalid("付款记录已被删除，请返回刷新后重试")
            }
            payment.amount = amount
            payment.dueDate = dueMs
            payment.isPaid = submittedPaid
            payment.paidDate = paidMs
            payment.reminderSet = submittedReminder
            payment.customReminderDays = days
            try await repo.update(payment)
        } else {
            let payment = Payment(priceId: priceId, amount: amount, dueDate: dueMs, isPaid: submittedPaid,
                                  paidDate: paidMs, reminderSet: submittedReminder, customReminderDays: days)
            paymentId = try await repo.insert(payment).id
        }
        baseline = formState
        if submittedReminder && !submittedPaid {
            reminderWarning = await reminderService?.requestNotificationAuthorization()
        }
        let result = await reminderService?.synchronize()
        reminderWarning = result?.warning
        return reminderWarning
    }
}
