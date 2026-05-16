import SwiftUI

enum ItemSubTab: String, CaseIterable {
    case location = "位置"
    case items = "服饰"
    case coordinate = "套装"
    case catalog = "图鉴"
}

@MainActor
final class ItemListViewModel: ObservableObject {
    @Published private(set) var items: [Item] = []
    @Published private(set) var locations: [Location] = []
    @Published private(set) var coordinates: [Coordinate] = []
    @Published var selectedSubTab: ItemSubTab = .items

    private let itemRepo = AppModule.shared.itemRepository
    private let locationRepo = AppModule.shared.locationRepository
    private let coordinateRepo = AppModule.shared.coordinateRepository

    func load() {
        Task {
            for await items in itemRepo.observeAll() { self.items = items }
        }
        Task {
            for await locations in locationRepo.observeAll() { self.locations = locations }
        }
        Task {
            for await coordinates in coordinateRepo.observeAll() { self.coordinates = coordinates }
        }
    }

    func itemsByStatus(_ status: ItemStatus) -> [Item] {
        items.filter { $0.status == status }
    }

    func itemsByLocation(_ locationId: Int64) -> [Item] {
        items.filter { $0.locationId == locationId }
    }

    func itemsByCoordinate(_ coordinateId: Int64) -> [Item] {
        items.filter { $0.coordinateId == coordinateId }
    }
}
