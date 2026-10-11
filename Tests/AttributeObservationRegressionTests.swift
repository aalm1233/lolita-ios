import XCTest
import GRDB
@testable import lolita

final class AttributeObservationRegressionTests: XCTestCase {
    @MainActor
    func testAllAttributeObserversPublishUpdatesAndStopOnCancellation() async throws {
        let database = try LolitaDatabase(path: ":memory:")
        for kind in AttributeKind.allCases {
            let vm = AttributeManageViewModel(db: database.dbQueue)
            try await vm.save(kind: kind, original: nil, name: "原名称", group: .clothing)
            let subscription = Task { await vm.observe(kind: kind) }
            defer { subscription.cancel() }
            try await waitForRows(kind: kind) { vm.rows.map(\.name) == ["原名称"] }

            let original = try XCTUnwrap(vm.rows.first)
            XCTAssertEqual(original.group, kind == .category ? .clothing : nil)
            try await vm.save(kind: kind, original: original, name: "新名称", group: .accessory)
            try await waitForRows(kind: kind) { vm.rows.map(\.name) == ["新名称"] }
            let updated = try XCTUnwrap(vm.rows.first)
            XCTAssertEqual(updated.id, original.id)
            XCTAssertEqual(updated.group, kind == .category ? .accessory : nil)

            try await vm.delete(kind: kind, row: updated)
            try await waitForRows(kind: kind) { vm.rows.isEmpty }
            subscription.cancel()
            await subscription.value

            try await vm.save(kind: kind, original: nil, name: "取消后新增", group: .clothing)
            try await Task.sleep(for: .milliseconds(30))
            XCTAssertTrue(vm.rows.isEmpty, "\(kind.rawValue)订阅取消后仍收到更新")
        }
    }

    @MainActor
    private func waitForRows(kind: AttributeKind, matching predicate: () -> Bool) async throws {
        for _ in 0..<100 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("\(kind.rawValue)管理未收到数据库更新")
    }
}
