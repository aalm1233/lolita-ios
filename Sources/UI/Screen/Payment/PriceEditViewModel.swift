import SwiftUI

@MainActor
final class PriceEditViewModel: ObservableObject {
    @Published var type: PriceType = .full
    @Published var totalPriceText: String = ""
    @Published var depositText: String = ""
    @Published var balanceText: String = ""
    @Published var isSaving: Bool = false

    nonisolated(unsafe) private let repo = AppModule.shared.priceRepository
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
        isSaving = true
        defer { isSaving = false }

        let totalPrice = Double(totalPriceText) ?? 0
        let deposit = depositText.isEmpty ? nil : Double(depositText)
        let balance = balanceText.isEmpty ? nil : Double(balanceText)

        if let priceId {
            guard var price = try await repo.getById(priceId) else { return }
            price.type = type
            price.totalPrice = totalPrice
            price.deposit = deposit
            price.balance = balance
            try await repo.update(price)
        } else {
            let price = Price(itemId: itemId, type: type, totalPrice: totalPrice, deposit: deposit, balance: balance)
            _ = try await repo.insert(price)
        }
    }
}
