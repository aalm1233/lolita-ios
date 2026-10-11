import XCTest
import GRDB
@testable import lolita

final class LocationEditorSaveRegressionTests: XCTestCase {
    @MainActor
    func testRepeatedLoadPreservesUnsavedInputsAndReplacementPhoto() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        let original = try imageFile(Data([11, 12, 13]))
        defer { ImageFileHelper.delete(path: original) }
        let repository = LocationRepository(db: database.dbQueue)
        let location = try await repository.insert(Location(name: "衣橱", description: "原备注", imageUrl: original))
        let vm = LocationEditViewModel(locationId: location.id, repository: repository)
        await vm.load()
        vm.name = "尚未保存的名称"
        vm.description = "尚未保存的备注"
        vm.setImage(data: Data([14, 15, 16]))
        let replacement = try XCTUnwrap(vm.imageUrl)
        defer { ImageFileHelper.delete(path: replacement) }

        // A native picker can cause the view's task to start again.
        await vm.load()
        XCTAssertEqual(vm.name, "尚未保存的名称")
        XCTAssertEqual(vm.description, "尚未保存的备注")
        XCTAssertEqual(vm.imageUrl, replacement)
        XCTAssertTrue(vm.hasChanges)
        let stored = try await repository.getById(location.id)
        XCTAssertEqual(stored?.name, "衣橱")
        XCTAssertEqual(stored?.imageUrl, original)
        vm.discardImages()
        XCTAssertFalse(FileManager.default.fileExists(atPath: replacement))
        XCTAssertTrue(FileManager.default.fileExists(atPath: original))
    }

    @MainActor
    func testSuccessfulSaveDefersDiscardAndProtectsCommittedPhoto() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        let original = try imageFile(Data([1, 2, 3]))
        defer { ImageFileHelper.delete(path: original) }
        let repository = LocationRepository(db: database.dbQueue)
        let location = try await repository.insert(Location(name: "原衣橱", imageUrl: original))
        let vm = LocationEditViewModel(locationId: location.id, repository: repository)
        await vm.load()
        vm.name = "新衣橱"
        vm.setImage(data: Data([4, 5, 6]))
        let replacement = try XCTUnwrap(vm.imageUrl)
        defer { ImageFileHelper.delete(path: replacement) }

        let gate = holdDatabase(database.dbQueue)
        defer { gate.release.signal() }
        let saving = Task { try await vm.save() }
        await waitUntilSaving(vm)

        // The UI can disappear while GRDB awaits its queue. Image mutations
        // and cancellation cleanup must leave this transaction's photo intact.
        vm.removeImage()
        vm.setImage(data: Data([7, 8, 9]))
        vm.discardImages()
        XCTAssertEqual(vm.imageUrl, replacement)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original))
        XCTAssertTrue(FileManager.default.fileExists(atPath: replacement))

        gate.release.signal()
        try await saving.value
        try await gate.blocker.value

        XCTAssertFalse(vm.isSaving)
        XCTAssertFalse(vm.hasChanges)
        let stored = try await repository.getById(location.id)
        XCTAssertEqual(stored?.name, "新衣橱")
        XCTAssertEqual(stored?.imageUrl, replacement)
        XCTAssertTrue(FileManager.default.fileExists(atPath: replacement))
        XCTAssertFalse(FileManager.default.fileExists(atPath: original))
        vm.discardImages()
        XCTAssertTrue(FileManager.default.fileExists(atPath: replacement))
    }

    @MainActor
    func testFailedSaveDefersDiscardThenCleansOnlyUncommittedPhoto() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        let original = try imageFile(Data([1, 3, 5]))
        defer { ImageFileHelper.delete(path: original) }
        let repository = LocationRepository(db: database.dbQueue)
        let location = try await repository.insert(Location(name: "位置甲", imageUrl: original))
        _ = try await repository.insert(Location(name: "位置乙"))
        let vm = LocationEditViewModel(locationId: location.id, repository: repository)
        await vm.load()
        vm.name = "位置乙"
        vm.setImage(data: Data([2, 4, 6]))
        let replacement = try XCTUnwrap(vm.imageUrl)
        defer { ImageFileHelper.delete(path: replacement) }

        let gate = holdDatabase(database.dbQueue)
        defer { gate.release.signal() }
        let saving = Task { try await vm.save() }
        await waitUntilSaving(vm)

        vm.removeImage()
        vm.setImage(data: Data([8, 9, 10]))
        vm.discardImages()
        XCTAssertEqual(vm.imageUrl, replacement)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original))
        XCTAssertTrue(FileManager.default.fileExists(atPath: replacement))

        gate.release.signal()
        do {
            try await saving.value
            XCTFail("重复位置名称应使数据库保存失败")
        } catch {
            XCTAssertEqual((error as? DatabaseError)?.extendedResultCode, .SQLITE_CONSTRAINT_UNIQUE)
        }
        try await gate.blocker.value

        XCTAssertFalse(vm.isSaving)
        let stored = try await repository.getById(location.id)
        XCTAssertEqual(stored?.name, "位置甲")
        XCTAssertEqual(stored?.imageUrl, original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original))
        XCTAssertFalse(FileManager.default.fileExists(atPath: replacement))
        vm.discardImages()
        XCTAssertTrue(FileManager.default.fileExists(atPath: original))
    }

    private func imageFile(_ data: Data) throws -> String {
        try XCTUnwrap(ImageFileHelper.save(imageData: data))
    }

    private struct DatabaseGate {
        let release: DispatchSemaphore
        let blocker: Task<Void, Error>
    }

    private func holdDatabase(_ db: DatabaseQueue) -> DatabaseGate {
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let blocker = Task.detached {
            try await db.read { _ in
                entered.signal()
                _ = release.wait(timeout: .now() + 10)
            }
        }
        XCTAssertEqual(entered.wait(timeout: .now() + 5), .success)
        return DatabaseGate(release: release, blocker: blocker)
    }

    @MainActor
    private func waitUntilSaving(_ viewModel: LocationEditViewModel) async {
        for _ in 0..<100 {
            if viewModel.isSaving { return }
            await Task.yield()
        }
        XCTAssertTrue(viewModel.isSaving, "保存任务应在数据库等待期间标记为保存中")
    }
}
