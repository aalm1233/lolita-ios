import SwiftUI

@MainActor
final class PaymentManageViewModel: ObservableObject {
    @Published private(set) var payments: [Payment] = []
    @Published private(set) var price: Price?
    let priceId: Int64

    private let paymentRepo = AppModule.shared.paymentRepository
    private let priceRepo = AppModule.shared.priceRepository

    init(priceId: Int64) { self.priceId = priceId }

    func load() async {
        price = try? await priceRepo.getById(priceId)
    }

    private var observationTask: Task<Void, Never>?

    func stopObserving() { observationTask?.cancel(); observationTask = nil }

    func observe() {
        guard observationTask == nil else { return }
        observationTask = Task { [weak self, paymentRepo, priceId] in
            for await ps in paymentRepo.getByPrice(priceId) {
                guard !Task.isCancelled else { return }
                self?.payments = ps
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
