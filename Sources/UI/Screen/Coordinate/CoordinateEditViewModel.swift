import SwiftUI

@MainActor
final class CoordinateEditViewModel: ObservableObject {
    @Published var name: String = ""
    @Published var description: String = ""
    @Published var imageUrls: [String] = []
    @Published var isSaving = false

    nonisolated(unsafe) private let coordinateRepo = AppModule.shared.coordinateRepository
    private var coordinateId: Int64?
    private var originalImageUrls: [String] = []

    func load(coordinateId: Int64) {
        self.coordinateId = coordinateId
        Task {
            guard let coordinate = try? await coordinateRepo.getById(coordinateId) else { return }
            self.name = coordinate.name
            self.description = coordinate.description
            self.imageUrls = coordinate.imageUrls.values
            self.originalImageUrls = coordinate.imageUrls.values
        }
    }

    var imageFileUrls: [URL] {
        imageUrls.compactMap { path in
            path.isEmpty ? nil : ImageFileHelper.fileURL(for: path)
        }
    }

    func addImageData(_ data: Data) {
        #if canImport(UIKit)
        guard let uiImage = UIImage(data: data),
              let path = ImageFileHelper.save(image: uiImage) else { return }
        #else
        guard let path = ImageFileHelper.save(imageData: data) else { return }
        #endif
        self.imageUrls.append(path)
    }

    func removeImage(at index: Int) {
        guard index < imageUrls.count else { return }
        let path = imageUrls[index]
        if !originalImageUrls.contains(path) {
            ImageFileHelper.delete(path: path)
        }
        imageUrls.remove(at: index)
    }

    func save() async throws {
        guard let coordinateId else { return }
        isSaving = true
        defer { isSaving = false }

        var coordinate = try await coordinateRepo.getById(coordinateId)
        coordinate?.name = name
        coordinate?.description = description
        coordinate?.imageUrls = StringList(imageUrls)

        guard let coordinate else { return }
        try await coordinateRepo.update(coordinate)

        // Clean up images that were removed
        let removed = Set(originalImageUrls).subtracting(Set(imageUrls))
        if !removed.isEmpty {
            ImageFileHelper.delete(paths: Array(removed))
        }
    }
}
