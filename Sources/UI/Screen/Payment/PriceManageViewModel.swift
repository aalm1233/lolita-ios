import SwiftUI

@MainActor
final class PriceManageViewModel: ObservableObject {
    @Published private(set) var prices: [Price] = []
    let itemId: Int64

    private let priceRepo = AppModule.shared.priceRepository

    init(itemId: Int64) { self.itemId = itemId }

    func load() async {
        prices = (try? await priceRepo.getByItem(itemId)) ?? []
    }

    func delete(_ price: Price) async throws {
        try await priceRepo.delete(price)
        await load()
    }
}
