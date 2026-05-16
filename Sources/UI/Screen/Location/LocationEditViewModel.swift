import SwiftUI

@MainActor
final class LocationEditViewModel: ObservableObject {
    @Published var name: String = ""
    @Published var description: String = ""
    @Published var imageUrl: String? = nil

    let locationId: Int64
    private let locationRepo = AppModule.shared.locationRepository
    private var originalLocation: Location?

    init(locationId: Int64) {
        self.locationId = locationId
    }

    func load() async {
        let location = await fetchLocation()
        guard let location else { return }
        originalLocation = location
        name = location.name
        description = location.description
        imageUrl = location.imageUrl
    }

    func save() async throws {
        guard var location = originalLocation else { return }
        location.name = name
        location.description = description
        location.imageUrl = imageUrl
        try await AppModule.shared.locationRepository.update(location)
    }

    func setImage(data: Data) {
        if let existingUrl = imageUrl {
            ImageFileHelper.delete(path: existingUrl)
        }
        imageUrl = ImageFileHelper.save(imageData: data)
    }

    func removeImage() {
        if let url = imageUrl {
            ImageFileHelper.delete(path: url)
        }
        imageUrl = nil
    }

    private nonisolated func fetchLocation() async -> Location? {
        let locationId = self.locationId
        return try? await AppModule.shared.locationRepository.getById(locationId)
    }
}
