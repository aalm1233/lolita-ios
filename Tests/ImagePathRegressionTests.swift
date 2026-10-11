import XCTest
import GRDB
@testable import lolita

final class ImagePathRegressionTests: XCTestCase {
    func testOldDeviceAndSimulatorPathsResolveOnlyToCurrentImages() throws {
        let fixture = try ImageDirectoryFixture()
        defer { fixture.remove() }
        let current = try fixture.image()
        let old = oldSandboxPath(for: current)
        let simulator = "/Users/example/Library/Developer/CoreSimulator/Devices/\(UUID().uuidString)/data" + old.dropFirst("/var/mobile".count)

        for path in [old, simulator, URL(fileURLWithPath: old).absoluteString] {
            XCTAssertEqual(ImageFileHelper.fileURL(for: path, imagesDirectory: fixture.images).path, current.path)
            XCTAssertTrue(ImageFileHelper.isOwnedFile(path, imagesDirectory: fixture.images))
            XCTAssertEqual(try Data(contentsOf: ImageFileHelper.fileURL(for: path, imagesDirectory: fixture.images)), Data([1, 2, 3]))
        }
    }

    func testCurrentAbsoluteAndFileURLPathsKeepTheirFiles() throws {
        let fixture = try ImageDirectoryFixture()
        defer { fixture.remove() }
        let current = try fixture.image()
        for path in [current.path, current.absoluteString] {
            XCTAssertEqual(ImageFileHelper.fileURL(for: path, imagesDirectory: fixture.images).path, current.path)
            XCTAssertTrue(ImageFileHelper.isOwnedFile(path, imagesDirectory: fixture.images))
        }
        let missing = fixture.images.appendingPathComponent("not-present.jpg")
        XCTAssertEqual(ImageFileHelper.fileURL(for: missing.path, imagesDirectory: fixture.images).path, missing.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
    }

    func testRemoteURLsRemainRemoteAndCannotDeleteLocalImages() throws {
        let fixture = try ImageDirectoryFixture()
        defer { fixture.remove() }
        let current = try fixture.image()
        for path in ["https://example.com/\(current.lastPathComponent)", "http://example.com/photo.jpg"] {
            XCTAssertEqual(ImageFileHelper.fileURL(for: path, imagesDirectory: fixture.images).absoluteString, path)
            XCTAssertFalse(ImageFileHelper.isOwnedFile(path, imagesDirectory: fixture.images))
            ImageFileHelper.delete(path: path, imagesDirectory: fixture.images)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: current.path))
    }

    func testExternalMissingAndTraversalPathsDoNotAliasCurrentImage() throws {
        let fixture = try ImageDirectoryFixture()
        defer { fixture.remove() }
        let current = try fixture.image()
        let external = fixture.root.appendingPathComponent(current.lastPathComponent)
        try Data([9, 8, 7]).write(to: external)
        let missingOld = oldSandboxPath(for: fixture.images.appendingPathComponent("missing.jpg"))
        let traversal = fixture.images.path + "/../images/" + current.lastPathComponent
        let encodedTraversal = fixture.images.absoluteString + "/%2e%2e/images/" + current.lastPathComponent
        let invalidContainer = oldSandboxPath(for: current).replacingOccurrences(of: "/Application/", with: "/Application/not-a-uuid/")

        for path in [external.path, external.absoluteString, missingOld, traversal, encodedTraversal, invalidContainer, current.lastPathComponent] {
            XCTAssertFalse(ImageFileHelper.isOwnedFile(path, imagesDirectory: fixture.images), path)
            let resolved = ImageFileHelper.fileURL(for: path, imagesDirectory: fixture.images)
            XCTAssertNotEqual(resolved.path, current.path, path)
            XCTAssertNotEqual(resolved.path, external.path, path)
            XCTAssertThrowsError(try Data(contentsOf: resolved), path)
            ImageFileHelper.delete(path: path, imagesDirectory: fixture.images)
        }
        XCTAssertEqual(try Data(contentsOf: external), Data([9, 8, 7]))
        XCTAssertEqual(try Data(contentsOf: current), Data([1, 2, 3]))
    }

    func testSymbolicLinksCannotReadOrDeleteExternalFiles() throws {
        let fixture = try ImageDirectoryFixture()
        defer { fixture.remove() }
        let external = fixture.root.appendingPathComponent("outside.jpg")
        try Data([9, 8, 7]).write(to: external)
        let link = fixture.images.appendingPathComponent("linked.jpg")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: external)
        for path in [link.path, oldSandboxPath(for: link)] {
            XCTAssertFalse(ImageFileHelper.isOwnedFile(path, imagesDirectory: fixture.images))
            XCTAssertThrowsError(try Data(contentsOf: ImageFileHelper.fileURL(for: path, imagesDirectory: fixture.images)))
            ImageFileHelper.delete(path: path, imagesDirectory: fixture.images)
        }
        XCTAssertEqual(try Data(contentsOf: external), Data([9, 8, 7]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: link.path))
    }

    func testStartupMigrationRewritesAllImageFieldsWithoutChangingBusinessData() throws {
        let fixture = try ImageDirectoryFixture()
        defer { fixture.remove() }
        let current = try fixture.image()
        let old = oldSandboxPath(for: current)
        let missing = oldSandboxPath(for: fixture.images.appendingPathComponent("missing.jpg"))
        let remote = "https://example.com/photo.jpg"
        let database = try LolitaDatabase(path: ":memory:")
        let itemID = try database.dbQueue.write { db in
            var brand = Brand(name: "品牌", logoUrl: old, createdAt: 11); try brand.insert(db)
            var category = Category(name: "分类"); try category.insert(db)
            var coordinate = Coordinate(name: "套装", description: "搭配描述", imageUrls: StringList([old, remote, missing]), createdAt: 12, updatedAt: 13); try coordinate.insert(db)
            var location = Location(name: "衣橱", description: "收纳描述", imageUrl: old, sortOrder: 2, createdAt: 14, updatedAt: 15); try location.insert(db)
            var item = Item(name: "服饰", brandId: brand.id, categoryId: category.id, status: .wished, priority: .high, description: "服饰描述", colors: StringList(["白色"]), season: "夏", style: "甜美", size: "M", sizeChartImageUrl: old, imageUrls: StringList([old, remote, missing]), coordinateId: coordinate.id, coordinateOrder: 3, locationId: location.id, source: "店铺", createdAt: 16, updatedAt: 17); try item.insert(db)
            var log = OutfitLog(date: 18000, note: "穿搭备注", imageUrls: StringList([old]), createdAt: 18, updatedAt: 19); try log.insert(db)
            try OutfitItemCrossRef(outfitLogId: log.id, itemId: item.id).insert(db)
            return item.id
        }

        XCTAssertEqual(try ImageFileHelper.migrateStoredPaths(db: database.dbQueue, imagesDirectory: fixture.images), 5)
        XCTAssertEqual(try ImageFileHelper.migrateStoredPaths(db: database.dbQueue, imagesDirectory: fixture.images), 0)
        try database.dbQueue.read { db in
            let item = try XCTUnwrap(Item.fetchOne(db, key: itemID))
            XCTAssertEqual(item.imageUrls.values, [current.path, remote, missing])
            XCTAssertEqual(item.sizeChartImageUrl, current.path)
            XCTAssertEqual(item.name, "服饰")
            XCTAssertEqual(item.description, "服饰描述")
            XCTAssertEqual(item.status, .wished)
            XCTAssertEqual(item.priority, .high)
            XCTAssertEqual(item.colors.values, ["白色"])
            XCTAssertEqual(item.season, "夏")
            XCTAssertEqual(item.style, "甜美")
            XCTAssertEqual(item.size, "M")
            XCTAssertEqual(item.source, "店铺")
            XCTAssertEqual(item.coordinateOrder, 3)
            XCTAssertEqual(item.createdAt, 16)
            XCTAssertEqual(item.updatedAt, 17)
            let coordinate = try XCTUnwrap(Coordinate.fetchOne(db, key: item.coordinateId))
            XCTAssertEqual(coordinate.imageUrls.values, [current.path, remote, missing])
            XCTAssertEqual(coordinate.description, "搭配描述")
            XCTAssertEqual(coordinate.createdAt, 12)
            XCTAssertEqual(coordinate.updatedAt, 13)
            let location = try XCTUnwrap(Location.fetchOne(db, key: item.locationId))
            XCTAssertEqual(location.imageUrl, current.path)
            XCTAssertEqual(location.description, "收纳描述")
            XCTAssertEqual(location.sortOrder, 2)
            XCTAssertEqual(location.updatedAt, 15)
            XCTAssertEqual(try Brand.fetchOne(db, key: item.brandId)?.logoUrl, current.path)
            XCTAssertEqual(try Brand.fetchOne(db, key: item.brandId)?.createdAt, 11)
            let log = try XCTUnwrap(OutfitLog.fetchAll(db).first)
            XCTAssertEqual(log.imageUrls.values, [current.path])
            XCTAssertEqual(log.date, 18000)
            XCTAssertEqual(log.note, "穿搭备注")
            XCTAssertEqual(log.createdAt, 18)
            XCTAssertEqual(log.updatedAt, 19)
            XCTAssertEqual(try OutfitItemCrossRef.fetchAll(db).first?.itemId, itemID)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: current.path))
    }

    func testCleanupProtectsSharedImageAcrossOldAndCurrentAliases() throws {
        let fixture = try ImageDirectoryFixture()
        defer { fixture.remove() }
        let current = try fixture.image()
        let old = oldSandboxPath(for: current)
        let database = try LolitaDatabase(path: ":memory:")
        let ids = try database.dbQueue.write { db in
            var brand = Brand(name: "品牌"); try brand.insert(db)
            var category = Category(name: "分类"); try category.insert(db)
            var first = Item(name: "服饰A", brandId: brand.id, categoryId: category.id, imageUrls: StringList([current.path])); try first.insert(db)
            var second = Item(name: "服饰B", brandId: brand.id, categoryId: category.id, sizeChartImageUrl: old); try second.insert(db)
            return [first.id, second.id]
        }
        try database.dbQueue.write { db in _ = try Item.deleteOne(db, key: ids[0]) }
        try ImageFileHelper.deleteUnreferenced(paths: [current.path], db: database.dbQueue, imagesDirectory: fixture.images)
        XCTAssertTrue(FileManager.default.fileExists(atPath: current.path))
        try database.dbQueue.write { db in _ = try Item.deleteOne(db, key: ids[1]) }
        try ImageFileHelper.deleteUnreferenced(paths: [old], db: database.dbQueue, imagesDirectory: fixture.images)
        XCTAssertFalse(FileManager.default.fileExists(atPath: current.path))
    }

    private func oldSandboxPath(for image: URL) -> String {
        "/var/mobile/Containers/Data/Application/01234567-89AB-CDEF-0123-456789ABCDEF/Documents/images/\(image.lastPathComponent)"
    }

    private struct ImageDirectoryFixture {
        let root: URL
        var images: URL { root.appendingPathComponent("images", isDirectory: true) }

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("lolita-image-path-tests-\(UUID().uuidString)", isDirectory: true)
                .resolvingSymlinksInPath()
            try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        }

        func image() throws -> URL {
            let url = images.appendingPathComponent("\(UUID().uuidString).jpg")
            try Data([1, 2, 3]).write(to: url)
            return url
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
