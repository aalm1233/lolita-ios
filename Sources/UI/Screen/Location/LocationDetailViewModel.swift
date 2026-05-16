import SwiftUI

@MainActor
final class LocationDetailViewModel: ObservableObject {
    @Published private(set) var location: Location?
    @Published private(set) var items: [Item] = []

    let locationId: Int64
    private let locationRepo = AppModule.shared.locationRepository
    private let itemRepo = AppModule.shared.itemRepository

    init(locationId: Int64) {
        self.locationId = locationId
    }

    func load() async {
        let result = await fetchLocationAndItems()
        location = result.location
        items = result.items
    }

    func delete() async throws {
        guard let location else { return }
        if let url = location.imageUrl {
            ImageFileHelper.delete(path: url)
        }
        try await AppModule.shared.locationRepository.delete(location)
    }

    private nonisolated func fetchLocationAndItems() async -> (location: Location?, items: [Item]) {
        let locationId = self.locationId
        let location = try? await AppModule.shared.locationRepository.getById(locationId)
        let items = (try? await AppModule.shared.itemRepository.getByLocation(locationId)) ?? []
        return (location, items)
    }
}
