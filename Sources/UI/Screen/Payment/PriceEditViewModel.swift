import SwiftUI

@MainActor
final class PriceEditViewModel: ObservableObject {
    @Published var type: PriceType = .full
    @Published var totalPriceText: String = ""
    @Published var depositText: String = ""
    @Published var balanceText: String = ""
    @Published var initialPaid = false
    @Published var paymentDate = Date()
    @Published var isSaving: Bool = false

    private let repo = AppModule.shared.priceRepository
    let itemId: Int64
    private(set) var priceId: Int64?

    init(itemId: Int64, priceId: Int64? = nil) {
        self.itemId = itemId
        self.priceId = priceId
    }

    func load() async {
        guard let priceId, let price = try? await repo.getById(priceId) else { return }
        type = price.type
        totalPriceText = String(format: "%.2f", price.totalPrice)
        if let d = price.deposit { depositText = String(format: "%.2f", d) }
        if let b = price.balance { balanceText = String(format: "%.2f", b) }
    }

    func save() async throws {
        guard !isSaving else { throw ValidationError.invalid("正在保存，请稍候") }
        isSaving = true
        defer { isSaving = false }

        let totalPrice = type == .full ? try InputValidation.amount(totalPriceText, label: "总价") : 0
        let deposit = depositText.isEmpty ? nil : try InputValidation.amount(depositText, label: "定金")
        let balance = balanceText.isEmpty ? nil : try InputValidation.amount(balanceText, label: "尾款")

        if let priceId {
            guard var price = try await repo.getById(priceId) else { return }
            price.type = type
            price.totalPrice = totalPrice
            price.deposit = deposit
            price.balance = balance
            _ = try await repo.saveWithPayments(price)
        } else {
            let price = Price(itemId: itemId, type: type, totalPrice: totalPrice, deposit: deposit, balance: balance)
            let saved = try await repo.saveWithPayments(price, initialPaidDate: initialPaid ? Int64(paymentDate.timeIntervalSince1970 * 1000) : nil)
            priceId = saved.id
        }
    }
}
