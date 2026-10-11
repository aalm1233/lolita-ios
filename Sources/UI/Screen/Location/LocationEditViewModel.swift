import SwiftUI

@MainActor
final class LocationEditViewModel: ObservableObject {
    @Published var name = ""
    @Published var description = ""
    @Published var imageUrl: String?
    @Published var isSaving = false
    let locationId: Int64
    private let repository: LocationRepository
    private var originalLocation: Location?
    private var originalState: [String]?
    private var discardRequested = false
    private var formState: [String] { [name, description, imageUrl ?? ""] }
    var hasChanges: Bool { originalState.map { $0 != formState } ?? false }

    init(locationId: Int64, repository: LocationRepository = AppModule.shared.locationRepository) { self.locationId = locationId; self.repository = repository }

    func load() async {
        guard originalState == nil, !isSaving else { return }
        guard locationId > 0 else { originalState = formState; return }
        let location = try? await repository.getById(locationId)
        guard !Task.isCancelled else { return }
        originalLocation = location
        if let location = originalLocation {
            name = location.name
            description = location.description
            imageUrl = location.imageUrl
            originalState = formState
        }
    }

    func save() async throws {
        guard !isSaving else { throw ValidationError.invalid("正在保存，请稍候") }
        isSaving = true
        defer {
            isSaving = false
            if discardRequested {
                discardRequested = false
                discardImages()
            }
        }
        if locationId > 0 && originalLocation == nil { throw ValidationError.invalid("位置不存在") }
        var location = originalLocation ?? Location(name: "")
        location.name = try InputValidation.name(name)
        location.description = description
        location.imageUrl = imageUrl
        let repo = repository
        if originalLocation == nil { location = try await repo.insert(location) }
        else { try await repo.update(location) }
        if let previous = originalLocation?.imageUrl, previous != location.imageUrl { try? repository.cleanupImages([previous]) }
        originalLocation = location
        originalState = [location.name, location.description, location.imageUrl ?? ""]
    }

    func setImage(data: Data) {
        guard !isSaving else { return }
        guard let path = ImageFileHelper.save(imageData: data) else { return }
        removeImage()
        imageUrl = path
    }

    func removeImage() {
        guard !isSaving else { return }
        if let path = imageUrl, path != originalLocation?.imageUrl { ImageFileHelper.delete(path: path) }
        imageUrl = nil
    }

    func discardImages() {
        guard !isSaving else { discardRequested = true; return }
        if let path = imageUrl, path != originalLocation?.imageUrl { ImageFileHelper.delete(path: path) }
    }
}
