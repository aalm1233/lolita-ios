import SwiftUI

@MainActor
final class PaymentManageViewModel: ObservableObject {
    @Published private(set) var payments: [Payment] = []
    @Published private(set) var price: Price?
    let priceId: Int64

    nonisolated(unsafe) private let paymentRepo = AppModule.shared.paymentRepository
    nonisolated(unsafe) private let priceRepo = AppModule.shared.priceRepository

    init(priceId: Int64) { self.priceId = priceId }

    func load() async {
        price = try? await priceRepo.getById(priceId)
    }

    func observe() {
        Task {
            for await ps in paymentRepo.getByPrice(priceId) {
                payments = ps
            }
        }
    }

    var totalAmount: Double {
        payments.reduce(0) { $0 + $1.amount }
    }

    var paidAmount: Double {
        payments.filter(\.isPaid).reduce(0) { $0 + $1.amount }
    }

    var remainingAmount: Double {
        totalAmount - paidAmount
    }

    func delete(_ payment: Payment) async throws {
        try await paymentRepo.delete(payment)
    }
}
