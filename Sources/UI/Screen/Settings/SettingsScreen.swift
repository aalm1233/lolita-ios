import SwiftUI
@preconcurrency import GRDB

struct SettingsScreen: View {
    var body: some View {
        List {
            Section("衣橱资料") {
                NavigationLink { BrandManageScreen() } label: { Label("品牌管理", systemImage: "tag") }
                NavigationLink { CategoryManageScreen() } label: { Label("分类管理", systemImage: "square.grid.2x2") }
                NavigationLink { StyleManageScreen() } label: { Label("风格管理", systemImage: "sparkles") }
                NavigationLink { SeasonManageScreen() } label: { Label("季节管理", systemImage: "leaf") }
                NavigationLink { LocationManageScreen() } label: { Label("位置管理", systemImage: "archivebox") }
                NavigationLink { AttributeManageScreen(kind: .source) } label: { Label("购买渠道管理", systemImage: "bag") }
            }
            Section("个性化") {
                NavigationLink { ThemeSelectScreen() } label: { Label("主题选择", systemImage: "paintpalette") }
            }
            Section("数据") {
                NavigationLink { BackupRestoreScreen() } label: { Label("备份与恢复", systemImage: "externaldrive") }
            }
        }
        .lolitaNavBar(title: "设置")
    }
}

enum AttributeKind: String, CaseIterable, Sendable {
    case brand = "品牌", category = "分类", style = "风格", season = "季节", source = "购买渠道"
    var table: String {
        switch self {
        case .brand: return "brands"
        case .category: return "categories"
        case .style: return "styles"
        case .season: return "seasons"
        case .source: return "sources"
        }
    }
    var reference: String? {
        switch self { case .style: return "style"; case .season: return "season"; case .source: return "source"; default: return nil }
    }
}

struct AttributeRow: Identifiable, Sendable {
    var id: Int64
    var name: String
    var group: CategoryGroup?
}

@MainActor
final class AttributeManageViewModel: ObservableObject {
    @Published var rows: [AttributeRow] = []
    private let queue: DatabaseQueue

    init(db: DatabaseQueue? = nil) {
        queue = db ?? AppModule.shared.db.dbQueue
    }

    func observe(kind: AttributeKind) async {
        for await rows in Self.rowUpdates(kind: kind, queue: queue) { self.rows = rows }
    }

    // GRDB fetches on its own queue. Build the callbacks outside MainActor so
    // Swift 6 does not inherit UI isolation into the database fetch closure.
    nonisolated private static func rowUpdates(kind: AttributeKind, queue: DatabaseQueue) -> AsyncStream<[AttributeRow]> {
        AsyncStream { continuation in
            let observation = ValueObservation.tracking { @Sendable db in
                try Row.fetchAll(db, sql: "SELECT * FROM \(kind.table) ORDER BY name").map { row in
                    AttributeRow(id: row["id"], name: row["name"], group: kind == .category ? row["group"] : nil)
                }
            }
            let token = observation.start(in: queue, onError: { _ in continuation.finish() }, onChange: { continuation.yield($0) })
            continuation.onTermination = { _ in token.cancel() }
        }
    }

    func save(kind: AttributeKind, original: AttributeRow?, name: String, group: CategoryGroup) async throws {
        let name = try InputValidation.name(name)
        try await queue.write { db in
            if let original {
                try db.execute(sql: "UPDATE \(kind.table) SET name = ? WHERE id = ?", arguments: [name, original.id])
                if let reference = kind.reference {
                    try db.execute(sql: "UPDATE items SET \(reference) = ?, updatedAt = ? WHERE \(reference) = ?", arguments: [name, Int64(Date().timeIntervalSince1970 * 1000), original.name])
                }
                if kind == .category { try db.execute(sql: "UPDATE categories SET \"group\" = ? WHERE id = ?", arguments: [group.rawValue, original.id]) }
            } else {
                let now = Int64(Date().timeIntervalSince1970 * 1000)
                if kind == .category {
                    try db.execute(sql: "INSERT INTO categories(name, \"group\", isPreset, createdAt) VALUES (?, ?, 0, ?)", arguments: [name, group.rawValue, now])
                } else {
                    try db.execute(sql: "INSERT INTO \(kind.table)(name, isPreset, createdAt) VALUES (?, 0, ?)", arguments: [name, now])
                }
            }
        }
    }

    func delete(kind: AttributeKind, row: AttributeRow) async throws {
        try await queue.write { db in
            if let reference = kind.reference {
                try db.execute(sql: "UPDATE items SET \(reference) = NULL, updatedAt = ? WHERE \(reference) = ?", arguments: [Int64(Date().timeIntervalSince1970 * 1000), row.name])
            }
            try db.execute(sql: "DELETE FROM \(kind.table) WHERE id = ?", arguments: [row.id])
        }
    }
}

struct AttributeManageScreen: View {
    let kind: AttributeKind
    @StateObject private var vm = AttributeManageViewModel()
    @State private var editing: AttributeRow?
    @State private var name = ""
    @State private var group: CategoryGroup = .clothing
    @State private var showEditor = false
    @State private var error: String?
    @State private var search = ""

    var body: some View {
        List {
            ForEach(vm.rows.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { row in
                Button {
                    editing = row; name = row.name; group = row.group ?? .clothing; showEditor = true
                } label: {
                    HStack { Text(row.name).foregroundStyle(.primary); Spacer(); Image(systemName: "pencil").foregroundStyle(.secondary) }
                }
                .swipeActions {
                    Button("删除", role: .destructive) {
                        Task { do { try await vm.delete(kind: kind, row: row) } catch { self.error = userFacingError(error) } }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "搜索\(kind.rawValue)")
        .lolitaNavBar(title: "\(kind.rawValue)管理", showBack: true)
        .toolbar { ToolbarItem { Button("添加") { editing = nil; name = ""; group = .clothing; showEditor = true } } }
        .sheet(isPresented: $showEditor) {
            NavigationStack {
                Form {
                    TextField("名称", text: $name)
                    if kind == .category {
                        Picker("分组", selection: $group) { Text("服装").tag(CategoryGroup.clothing); Text("配饰").tag(CategoryGroup.accessory) }
                    }
                }
                .navigationTitle(editing == nil ? "新增\(kind.rawValue)" : "编辑\(kind.rawValue)")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { showEditor = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            Task {
                                do { try await vm.save(kind: kind, original: editing, name: name, group: group); showEditor = false }
                                catch { self.error = userFacingError(error) }
                            }
                        }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .alert("操作失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("确定") { error = nil }
                } message: { Text(error ?? "") }
            }
        }
        .alert("操作失败", isPresented: Binding(get: { error != nil && !showEditor }, set: { if !$0 { error = nil } })) {
            Button("确定") { error = nil }
        } message: { Text(error ?? "") }
        .task { await vm.observe(kind: kind) }
    }
}

struct LocationManageScreen: View {
    @State private var locations: [Location] = []
    @State private var error: String?
    var body: some View {
        List(locations, id: \.id) { location in
            NavigationLink(location.name) { LocationDetailScreen(locationId: location.id) }
                .swipeActions {
                    Button("删除", role: .destructive) {
                        Task { do { try await AppModule.shared.locationRepository.delete(location) } catch { self.error = userFacingError(error) } }
                    }
                }
        }
        .lolitaNavBar(title: "位置管理", showBack: true)
        .toolbar { ToolbarItem { NavigationLink(destination: LocationEditScreen()) { Image(systemName: "plus") } } }
        .task { for await value in AppModule.shared.locationRepository.observeAll() { locations = value } }
        .alert("操作失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("确定") { error = nil } } message: { Text(error ?? "") }
    }
}
