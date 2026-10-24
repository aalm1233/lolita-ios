import SwiftUI
@preconcurrency import GRDB

@MainActor
final class PriceManageViewModel: ObservableObject {
    @Published private(set) var orders: [OrderSnapshot] = []
    @Published private(set) var ownerId: Int64
    @Published private(set) var isShared = false
    @Published private(set) var error: String?
    @Published private(set) var isLoading = true
    let itemId: Int64
    private let repository: OrderRepository

    init(itemId: Int64, db: DatabaseQueue = AppModule.shared.db.dbQueue) {
        self.itemId = itemId; ownerId = itemId
        repository = OrderRepository(db: db)
    }

    func observe() async {
        do {
            let owner = try await repository.owner(itemId: itemId)
            ownerId = owner.id; isShared = owner.id != itemId
            for await values in repository.observe(itemId: itemId) {
                guard !Task.isCancelled else { return }
                orders = values; isLoading = false
            }
        } catch { self.error = userFacingError(error); isLoading = false }
    }
}
