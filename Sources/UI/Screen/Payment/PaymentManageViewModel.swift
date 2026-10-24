import SwiftUI

@MainActor
final class PaymentManageViewModel: ObservableObject {
    @Published private(set) var order: OrderSnapshot?
    @Published private(set) var error: String?
    @Published var isWorking = false
    let priceId: Int64
    private let repository = AppModule.shared.orderRepository
    init(priceId: Int64) { self.priceId = priceId }

    func observe() async {
        do {
            let first = try await repository.get(priceId)
            order = first
            for await values in repository.observe(itemId: first.price.itemId) {
                guard !Task.isCancelled else { return }
                order = values.first { $0.id == priceId }
            }
        } catch { self.error = userFacingError(error) }
    }

    func bind() async throws {
        guard let order else { return }
        try await repository.bindHistorical(itemId: order.price.itemId, priceId: priceId)
    }
    func confirm(historical: Bool) async throws {
        guard let order else { return }
        try await repository.confirmPurchase(priceId: priceId, historicalOwned: historical, paymentsVerified: !historical, expected: order.fingerprint)
    }
    func archive() async throws { try await repository.archive(priceId: priceId, expected: order?.fingerprint) }
    func delete(_ payment: Payment) async throws { try await repository.deletePayment(payment.id, expected: order?.fingerprint) }
}
