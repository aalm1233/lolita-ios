import XCTest
import GRDB
@testable import lolita

final class EditorImageRegressionTests: XCTestCase {
    @MainActor
    func testRemovingNewSizeChartDeletesItsFile() throws {
        let database = try LolitaDatabase(path: ":memory:")
        let vm = ItemEditViewModel(db: database.dbQueue)
        vm.setSizeChart(data: Data([1, 2, 3]))
        let path = try XCTUnwrap(vm.sizeChartImageUrl)
        defer { ImageFileHelper.delete(path: path) }

        vm.removeSizeChart()
        XCTAssertNil(vm.sizeChartImageUrl)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
        vm.discardImages()
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    @MainActor
    func testRemovingReplacementSizeChartKeepsCommittedOriginalOnCancel() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        let original = try imageFile()
        defer { ImageFileHelper.delete(path: original) }
        let item = try await makeItem(database.dbQueue, chart: original)
        let vm = ItemEditViewModel(db: database.dbQueue)
        await vm.load(itemId: item.id)
        vm.setSizeChart(data: Data([4, 5, 6]))
        let replacement = try XCTUnwrap(vm.sizeChartImageUrl)
        defer { ImageFileHelper.delete(path: replacement) }

        vm.removeSizeChart()
        vm.discardImages()
        XCTAssertTrue(FileManager.default.fileExists(atPath: original))
        XCTAssertFalse(FileManager.default.fileExists(atPath: replacement))
        let stored = try await ItemRepository(db: database.dbQueue).getById(item.id)
        XCTAssertEqual(stored?.sizeChartImageUrl, original)
    }

    @MainActor
    func testCancelPhotoEditsPreservesCommittedFilesForAllEditors() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        let original = try imageFile()
        let added = try imageFile()
        defer { ImageFileHelper.delete(paths: [original, added]) }
        let item = try await makeItem(database.dbQueue, image: original)
        let coordinate = try await CoordinateRepository(db: database.dbQueue).insert(
            Coordinate(name: "套装", description: "", imageUrls: StringList([original]))
        )
        let log = try await OutfitLogRepository(db: database.dbQueue).insert(
            OutfitLog(date: 1000, note: "", imageUrls: StringList([original]))
        )

        let itemVM = ItemEditViewModel(db: database.dbQueue)
        await itemVM.load(itemId: item.id)
        itemVM.imageUrls.append(added)
        itemVM.removeImage(at: 0)
        itemVM.discardImages()
        XCTAssertTrue(FileManager.default.fileExists(atPath: original))
        XCTAssertFalse(FileManager.default.fileExists(atPath: added))

        let coordinateAdded = try imageFile()
        defer { ImageFileHelper.delete(path: coordinateAdded) }
        let coordinateVM = CoordinateEditViewModel(db: database.dbQueue)
        await coordinateVM.load(coordinateId: coordinate.id)
        coordinateVM.imageUrls.append(coordinateAdded)
        coordinateVM.removeImage(at: 0)
        coordinateVM.discardImages()
        XCTAssertTrue(FileManager.default.fileExists(atPath: original))
        XCTAssertFalse(FileManager.default.fileExists(atPath: coordinateAdded))

        let logAdded = try imageFile()
        defer { ImageFileHelper.delete(path: logAdded) }
        let logVM = OutfitLogEditViewModel(db: database.dbQueue)
        await logVM.load(logId: log.id)
        logVM.imageUrls.append(logAdded)
        logVM.removeImage(at: 0)
        logVM.discardImages()
        XCTAssertTrue(FileManager.default.fileExists(atPath: original))
        XCTAssertFalse(FileManager.default.fileExists(atPath: logAdded))
    }

    @MainActor
    func testRepeatedLoadKeepsUnsavedInputsAndNewPhotosForAllEditors() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        let item = try await makeItem(database.dbQueue)
        let coordinate = try await CoordinateRepository(db: database.dbQueue).insert(Coordinate(name: "套装", description: ""))
        let log = try await OutfitLogRepository(db: database.dbQueue).insert(OutfitLog(date: 1000, note: "备注"))
        let added = try imageFile()
        defer { ImageFileHelper.delete(path: added) }

        let itemVM = ItemEditViewModel(db: database.dbQueue)
        await itemVM.load(itemId: item.id)
        itemVM.name = "未保存服饰"
        itemVM.imageUrls = [added]
        await itemVM.load(itemId: item.id)
        XCTAssertEqual(itemVM.name, "未保存服饰")
        XCTAssertEqual(itemVM.imageUrls, [added])
        XCTAssertTrue(itemVM.hasChanges)

        let coordinateVM = CoordinateEditViewModel(db: database.dbQueue)
        await coordinateVM.load(coordinateId: coordinate.id)
        coordinateVM.name = "未保存套装"
        coordinateVM.imageUrls = [added]
        coordinateVM.toggleItem(item.id)
        await coordinateVM.load(coordinateId: coordinate.id)
        XCTAssertEqual(coordinateVM.name, "未保存套装")
        XCTAssertEqual(coordinateVM.imageUrls, [added])
        XCTAssertEqual(coordinateVM.selectedItemIds, [item.id])
        XCTAssertTrue(coordinateVM.hasChanges)

        let outfitVM = OutfitLogEditViewModel(db: database.dbQueue)
        await outfitVM.load(logId: log.id)
        outfitVM.note = "未保存备注"
        outfitVM.imageUrls = [added]
        outfitVM.toggleItem(item.id)
        await outfitVM.load(logId: log.id)
        XCTAssertEqual(outfitVM.note, "未保存备注")
        XCTAssertEqual(outfitVM.imageUrls, [added])
        XCTAssertEqual(outfitVM.selectedItemIds, Set([item.id]))
        XCTAssertTrue(outfitVM.hasChanges)

        let newItemVM = ItemEditViewModel(db: database.dbQueue)
        await newItemVM.load(itemId: 0)
        newItemVM.name = "新增服饰输入"
        newItemVM.imageUrls = [added]
        await newItemVM.load(itemId: 0, defaultStatus: .wished)
        XCTAssertEqual(newItemVM.name, "新增服饰输入")
        XCTAssertEqual(newItemVM.imageUrls, [added])
        XCTAssertEqual(newItemVM.status, .owned)

        let newCoordinateVM = CoordinateEditViewModel(db: database.dbQueue)
        await newCoordinateVM.load(coordinateId: 0)
        newCoordinateVM.name = "新增套装输入"
        newCoordinateVM.imageUrls = [added]
        await newCoordinateVM.load(coordinateId: 0)
        XCTAssertEqual(newCoordinateVM.name, "新增套装输入")
        XCTAssertEqual(newCoordinateVM.imageUrls, [added])
        XCTAssertTrue(FileManager.default.fileExists(atPath: added))
    }

    @MainActor
    func testItemSaveProtectsFilesAndUsesCommittedSnapshot() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        let item = try await makeItem(database.dbQueue)
        let vm = ItemEditViewModel(db: database.dbQueue)
        await vm.load(itemId: item.id)
        let committed = try imageFile()
        let late = try imageFile()
        defer { ImageFileHelper.delete(paths: [committed, late]) }
        vm.imageUrls = [committed]
        vm.setSizeChart(data: Data([1, 2, 3]))
        let chart = try XCTUnwrap(vm.sizeChartImageUrl)
        defer { ImageFileHelper.delete(path: chart) }

        vm.composition = .pair
        vm.specifications.profiles["footwear"] = ["heelHeightCm": "5–7"]
        vm.sizeChartImageUrls = [chart, committed]
        let gate = holdDatabase(database.dbQueue)
        defer { gate.release.signal() }
        let saving = Task { try await vm.save() }
        await waitUntilSaving { vm.isSaving }
        vm.removeImage(at: 0)
        vm.removeSizeChart()
        vm.setSizeChart(data: Data([9, 8, 7]))
        vm.addImageData(Data([9, 8, 7]))
        vm.discardImages()
        XCTAssertEqual(vm.imageUrls, [committed])
        XCTAssertEqual(vm.sizeChartImageUrl, chart)
        XCTAssertTrue(FileManager.default.fileExists(atPath: committed))
        XCTAssertTrue(FileManager.default.fileExists(atPath: chart))

        // Published inputs remain public; even an external change must not
        // redefine the image set that the pending transaction committed.
        vm.imageUrls = [late]
        vm.name = "事务之后的输入"
        vm.composition = .set
        vm.specifications.profiles["footwear"] = ["heelHeightCm": "99"]
        vm.sizeChartImageUrls = [late]
        gate.release.signal()
        try await saving.value
        try await gate.blocker.value
        let stored = try await ItemRepository(db: database.dbQueue).getById(item.id)
        XCTAssertEqual(stored?.imageUrls.values, [committed])
        XCTAssertEqual(stored?.sizeChartImageUrl, chart)
        XCTAssertEqual(stored?.name, item.name)
        XCTAssertEqual(stored?.composition, .pair)
        XCTAssertEqual(stored?.sizeChartImageUrls.values, [chart, committed])
        XCTAssertEqual(try WardrobeSpecifications.decode(stored?.specificationsJson ?? "").profiles["footwear"]?["heelHeightCm"], "5–7")
        vm.discardImages()
        XCTAssertTrue(FileManager.default.fileExists(atPath: committed))
        XCTAssertTrue(FileManager.default.fileExists(atPath: chart))
        XCTAssertFalse(FileManager.default.fileExists(atPath: late))
    }

    @MainActor
    func testCoordinateSaveProtectsFilesAndSelectedItemSnapshot() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        let item = try await makeItem(database.dbQueue)
        let repo = CoordinateRepository(db: database.dbQueue)
        let coordinate = try await repo.insert(Coordinate(name: "套装", description: ""))
        let vm = CoordinateEditViewModel(db: database.dbQueue)
        await vm.load(coordinateId: coordinate.id)
        let committed = try imageFile()
        let late = try imageFile()
        defer { ImageFileHelper.delete(paths: [committed, late]) }
        vm.imageUrls = [committed]
        vm.toggleItem(item.id)

        let gate = holdDatabase(database.dbQueue)
        defer { gate.release.signal() }
        let saving = Task { try await vm.save() }
        await waitUntilSaving { vm.isSaving }
        vm.removeImage(at: 0)
        vm.toggleItem(item.id)
        vm.discardImages()
        XCTAssertEqual(vm.imageUrls, [committed])
        XCTAssertEqual(vm.selectedItemIds, [item.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: committed))
        vm.imageUrls = [late]
        vm.selectedItemIds = []
        gate.release.signal()
        try await saving.value
        try await gate.blocker.value
        let stored = try await repo.getById(coordinate.id)
        let savedItems = try await repo.getItems(for: coordinate.id)
        XCTAssertEqual(stored?.imageUrls.values, [committed])
        XCTAssertEqual(savedItems.map(\.id), [item.id])
        vm.discardImages()
        XCTAssertTrue(FileManager.default.fileExists(atPath: committed))
        XCTAssertFalse(FileManager.default.fileExists(atPath: late))
    }

    @MainActor
    func testOutfitSaveProtectsFilesAndSelectedItemSnapshot() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        let item = try await makeItem(database.dbQueue)
        let repo = OutfitLogRepository(db: database.dbQueue)
        let log = try await repo.insert(OutfitLog(date: 1000, note: "原备注"))
        let vm = OutfitLogEditViewModel(db: database.dbQueue)
        await vm.load(logId: log.id)
        let committed = try imageFile()
        let late = try imageFile()
        defer { ImageFileHelper.delete(paths: [committed, late]) }
        vm.imageUrls = [committed]
        vm.toggleItem(item.id)

        let gate = holdDatabase(database.dbQueue)
        defer { gate.release.signal() }
        let saving = Task { try await vm.save() }
        await waitUntilSaving { vm.isSaving }
        vm.removeImage(at: 0)
        vm.toggleItem(item.id)
        vm.discardImages()
        XCTAssertEqual(vm.imageUrls, [committed])
        XCTAssertEqual(vm.selectedItemIds, Set([item.id]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: committed))
        vm.imageUrls = [late]
        vm.selectedItemIds = []
        vm.note = "事务之后的备注"
        gate.release.signal()
        try await saving.value
        try await gate.blocker.value
        let stored = try await repo.getById(log.id)
        let savedIds = try await repo.getItemIds(for: log.id)
        XCTAssertEqual(stored?.imageUrls.values, [committed])
        XCTAssertEqual(stored?.note, "原备注")
        XCTAssertEqual(savedIds, [item.id])
        vm.discardImages()
        XCTAssertTrue(FileManager.default.fileExists(atPath: committed))
        XCTAssertFalse(FileManager.default.fileExists(atPath: late))
    }

    private func imageFile() throws -> String {
        try XCTUnwrap(ImageFileHelper.save(imageData: Data([1, 2, 3])))
    }

    @MainActor
    private func makeItem(_ db: DatabaseQueue, chart: String? = nil, image: String? = nil) async throws -> Item {
        try await db.write { db in
            var brand = Brand(name: "品牌"); try brand.insert(db)
            var category = Category(name: "分类"); try category.insert(db)
            var item = Item(name: "服饰", brandId: brand.id, categoryId: category.id, sizeChartImageUrl: chart, imageUrls: StringList([image].compactMap { $0 }))
            try item.insert(db)
            return item
        }
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
    private func waitUntilSaving(_ isSaving: () -> Bool) async {
        for _ in 0..<100 {
            if isSaving() { return }
            await Task.yield()
        }
        XCTAssertTrue(isSaving(), "保存任务应在数据库等待期间标记为保存中")
    }
}
