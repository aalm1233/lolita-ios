import SwiftUI

@MainActor
final class PaymentEditViewModel: ObservableObject {
    @Published var amountText: String = ""
    @Published var dueDate: Date = Date()
    @Published var isPaid: Bool = false
    @Published var paidDate: Date = Date()
    @Published var isSaving: Bool = false

    nonisolated(unsafe) private let repo = AppModule.shared.paymentRepository
    let priceId: Int64
    private(set) var paymentId: Int64?

    init(priceId: Int64, paymentId: Int64? = nil) {
        self.priceId = priceId
        self.paymentId = paymentId
    }

    func load() async {
        guard let paymentId, let payment = try? await repo.getById(paymentId) else { return }
        amountText = String(format: "%.2f", payment.amount)
        dueDate = Date(timeIntervalSince1970: TimeInterval(payment.dueDate) / 1000)
        isPaid = payment.isPaid
        if let pd = payment.paidDate {
            paidDate = Date(timeIntervalSince1970: TimeInterval(pd) / 1000)
        }
    }

    func save() async throws {
        isSaving = true
        defer { isSaving = false }

        let amount = Double(amountText) ?? 0
        let dueMs = Int64(dueDate.timeIntervalSince1970 * 1000)
        let paidMs = isPaid ? Int64(paidDate.timeIntervalSince1970 * 1000) : nil

        if let paymentId {
            guard var payment = try await repo.getById(paymentId) else { return }
            payment.amount = amount
            payment.dueDate = dueMs
            payment.isPaid = isPaid
            payment.paidDate = paidMs
            try await repo.update(payment)
        } else {
            let payment = Payment(priceId: priceId, amount: amount, dueDate: dueMs, isPaid: isPaid, paidDate: paidMs)
            _ = try await repo.insert(payment)
        }
    }
}
