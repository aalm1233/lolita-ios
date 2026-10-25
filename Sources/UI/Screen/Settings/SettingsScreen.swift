import SwiftUI
@preconcurrency import GRDB
#if os(iOS)
import PhotosUI
#endif

struct SettingsScreen: View {
    @EnvironmentObject private var skinManager: SkinManager
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("profileNickname") private var nickname = ""
    @AppStorage("profileAvatarPath") private var avatarPath = ""
    @AppStorage("showTotalPrice") private var showTotalPrice = true
    @State private var items: [Item] = []
    @State private var coordinates: [Coordinate] = []
    @State private var totalSpent = 0.0
    @State private var showNicknameEditor = false
    @State private var nicknameDraft = ""
    @State private var error: String?
    #if os(iOS)
    @State private var pickedAvatar: PhotosPickerItem?
    @State private var avatarTask: Task<Void, Never>?
    @State private var avatarImportId: UUID?
    #endif

    private var accent: Color { colorScheme == .dark ? skinManager.current.accentColorDark : skinManager.current.accentColor }

    var body: some View {
        let displayedAvatar = avatarPath
        let displayedAccent = accent
        VStack(spacing: 0) {
            LolitaRootToolbar(title: "个人") { EmptyView() }
            ScrollView {
                VStack(spacing: 14) {
                    PersonalProfileCard(nickname: nickname, avatarPath: avatarPath,
                                        itemCount: items.filter { $0.status != .wished }.count,
                                        coordinateCount: coordinates.count, totalSpent: totalSpent,
                                        onEditNickname: { nicknameDraft = nickname; showNicknameEditor = true }) {
                        #if os(iOS)
                        PhotosPicker(selection: $pickedAvatar, matching: .images) {
                            PersonalAvatarView(path: displayedAvatar, color: displayedAccent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("设置头像")
                        #else
                        PersonalAvatarView(path: displayedAvatar, color: displayedAccent)
                        #endif
                    }

                    NavigationLink { AttributeSettingsScreen() } label: {
                        SettingsMenuCard(title: "属性管理", subtitle: "品牌、分类、风格、季节、位置与渠道", symbol: "square.grid.2x2", color: .purple)
                    }.accessibilityIdentifier("attribute-settings")
                    NavigationLink { BackupRestoreScreen() } label: {
                        SettingsMenuCard(title: "数据备份与恢复", subtitle: "ZIP 图片备份、安卓备份恢复与全表 CSV", symbol: "externaldrive", color: .blue)
                    }
                    NavigationLink { ProductImportScreen() } label: { SettingsMenuCard(title: "商品链接登记", subtitle: "读取商品资料，核对后登记心愿", symbol: "link", color: .orange) }.accessibilityIdentifier("商品链接登记")
                    NavigationLink { TaobaoImportScreen() } label: {
                        SettingsMenuCard(title: "淘宝订单导入", subtitle: "选择订单 Excel，核对定金尾款后导入", symbol: "cart", color: .orange)
                    }.accessibilityIdentifier("淘宝订单导入")
                    NavigationLink { FinanceOverviewScreen() } label: {
                        SettingsMenuCard(title: "预算与资金", subtitle: "月预算、退款、净支出与年度付款", symbol: "yensign.circle", color: .mint)
                    }.accessibilityIdentifier("finance-overview")
                    NavigationLink { ReminderSettingsScreen() } label: {
                        SettingsMenuCard(title: "提醒与系统日历", subtitle: "付款通知、日历联动和每日穿搭提醒", symbol: "bell", color: .teal)
                    }
                    NavigationLink { ThemeSelectScreen() } label: {
                        SettingsMenuCard(title: "皮肤选择", subtitle: skinManager.currentSkinType.displayName, symbol: "paintpalette", color: accent)
                    }.accessibilityIdentifier("theme-settings")
                    LolitaSection(title: "显示设置") {
                        Toggle(isOn: $showTotalPrice) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("显示金额").font(.subheadline.weight(.medium))
                                Text("在列表、详情、账本和统计显示金额；主动编辑或核对时临时显示")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .tint(accent).accessibilityIdentifier("显示总价")
                        Text("皮肤字体用于标题；正文、输入框和金额使用系统字体，字号跟随系统设置。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
        }
        .lolitaNavBar(title: "个人", isHidden: true)
        .task { for await value in AppModule.shared.itemRepository.observeAll() { items = value } }
        .task { for await value in AppModule.shared.coordinateRepository.observeAll() { coordinates = value } }
        .task { for await value in AppModule.shared.priceRepository.getTotalSpending() { totalSpent = value } }
        .alert("设置昵称", isPresented: $showNicknameEditor) {
            TextField("昵称", text: $nicknameDraft)
            Button("保存") { nickname = String(nicknameDraft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30)) }
            Button("取消", role: .cancel) { }
        }
        .alert("头像设置失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("确定") { error = nil }
        } message: { Text(error ?? "") }
        #if os(iOS)
        .onChange(of: pickedAvatar) { _, selection in
            avatarTask?.cancel()
            guard let selection else { return }
            let requestId = UUID()
            avatarImportId = requestId
            avatarTask = Task {
                defer {
                    if avatarImportId == requestId {
                        avatarTask = nil
                        avatarImportId = nil
                        pickedAvatar = nil
                    }
                }
                do {
                    guard let data = try await selection.loadTransferable(type: Data.self),
                          !Task.isCancelled, avatarImportId == requestId, let image = UIImage(data: data),
                          let path = ImageFileHelper.save(image: image) else {
                        if !Task.isCancelled { error = "无法读取这张图片，请重新选择。" }
                        return
                    }
                    let old = avatarPath
                    avatarPath = path
                    if !old.isEmpty { try? ImageFileHelper.deleteUnreferenced(paths: [old], db: AppModule.shared.db.dbQueue) }
                } catch { if !Task.isCancelled { self.error = userFacingError(error) } }
            }
        }
        .onDisappear {
            avatarTask?.cancel()
            avatarTask = nil
            avatarImportId = nil
            pickedAvatar = nil
        }
        #endif
    }

}

struct PersonalAvatarView: View {
    let path: String
    let color: Color
    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.12))
            if !path.isEmpty {
                LolitaShimmerImage(url: ImageFileHelper.fileURL(for: path))
            } else {
                SkinIcon(systemName: "heart.fill", size: 28).foregroundStyle(color)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(Circle())
        .overlay(alignment: .bottomTrailing) {
            SkinIcon(systemName: "camera.fill", size: 10)
                .foregroundStyle(.white).padding(5).background(color, in: Circle())
        }
    }
}

struct PersonalProfileCard<Avatar: View>: View {
    @AppStorage("showTotalPrice") private var showTotalPrice = true
    @EnvironmentObject private var skinManager: SkinManager
    @Environment(\.colorScheme) private var colorScheme
    let nickname: String
    let avatarPath: String
    let itemCount: Int
    let coordinateCount: Int
    let totalSpent: Double
    let onEditNickname: () -> Void
    @ViewBuilder let avatar: () -> Avatar

    var body: some View {
        LolitaCard {
            HStack(spacing: 12) {
                avatar()
                VStack(alignment: .leading, spacing: 5) {
                    Button(action: onEditNickname) {
                        HStack(spacing: 5) {
                            Text(nickname.isEmpty ? "点击设置昵称" : nickname).font(.headline).lineLimit(1)
                            SkinIcon(systemName: "pencil", size: 12)
                        }
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    Text("\(itemCount) 件服饰 · \(coordinateCount) 套搭配")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("已录实付").font(.caption2).foregroundStyle(.secondary)
                        Text(showTotalPrice ? totalSpent.formatted(.currency(code: "CNY").precision(.fractionLength(0))) : "金额已隐藏")
                            .font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(colorScheme == .dark ? skinManager.current.accentColorDark : skinManager.current.accentColor)
                            .lineLimit(1).minimumScaleFactor(0.65)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct SettingsMenuCard: View {
    let title: String
    let subtitle: String
    let symbol: String
    let color: Color
    var body: some View {
        LolitaCard(variant: .compact) {
            HStack(spacing: 13) {
                SkinIcon(systemName: symbol).foregroundStyle(color)
                    .frame(width: 44, height: 44).background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                SkinIcon(systemName: "chevron.right", size: 12).foregroundStyle(.tertiary)
            }
            .padding(4)
        }
    }
}

struct AttributeSettingsScreen: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                NavigationLink { BrandManageScreen() } label: { SettingsMenuCard(title: "品牌", subtitle: "管理衣橱品牌", symbol: "tag", color: .pink) }.accessibilityIdentifier("brand-management")
                NavigationLink { CategoryManageScreen() } label: { SettingsMenuCard(title: "分类", subtitle: "服饰与配饰类型", symbol: "square.grid.2x2", color: .purple) }.accessibilityIdentifier("category-management")
                NavigationLink { StyleManageScreen() } label: { SettingsMenuCard(title: "风格", subtitle: "搭配风格与偏好", symbol: "sparkles", color: .orange) }
                NavigationLink { SeasonManageScreen() } label: { SettingsMenuCard(title: "季节", subtitle: "服饰适用季节", symbol: "leaf", color: .green) }
                NavigationLink { LocationManageScreen() } label: { SettingsMenuCard(title: "位置", subtitle: "衣柜与收纳位置", symbol: "archivebox", color: .teal) }
                NavigationLink { AttributeManageScreen(kind: .source) } label: { SettingsMenuCard(title: "购买渠道", subtitle: "店铺与来源", symbol: "bag", color: .blue) }
            }
            .buttonStyle(.plain).padding(16)
        }
        .lolitaNavBar(title: "属性管理", showBack: true)
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
    var semantic: CategorySemantic = .unconfirmed
    var logoUrl: String?
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
                    AttributeRow(id: row["id"], name: row["name"], group: kind == .category ? row["group"] : nil, semantic: kind == .category ? row["categorySemantic"] : .unconfirmed, logoUrl: kind == .brand ? row["logoUrl"] : nil)
                }
            }
            let token = observation.start(in: queue, onError: { _ in continuation.finish() }, onChange: { continuation.yield($0) })
            continuation.onTermination = { _ in token.cancel() }
        }
    }

    func save(kind: AttributeKind, original: AttributeRow?, name: String, group: CategoryGroup, semantic: CategorySemantic? = nil, removeLogo: Bool = false) async throws {
        let name = try kind == .season ? SeasonRepository.validatedName(name) : InputValidation.name(name)
        if kind == .brand, original == nil {
            _ = try await BrandRepository(db: queue).insert(Brand(name: name))
            return
        }
        try await queue.write { db in
            if let original {
                try db.execute(sql: "UPDATE \(kind.table) SET name = ? WHERE id = ?", arguments: [name, original.id])
                if kind == .brand, removeLogo { try db.execute(sql: "UPDATE brands SET logoUrl = NULL WHERE id = ?", arguments: [original.id]) }
                if kind == .season {
                    try SeasonRepository.rewriteItemReferences(in: db, oldName: original.name, newName: name)
                } else if let reference = kind.reference {
                    try db.execute(sql: "UPDATE items SET \(reference) = ?, updatedAt = ? WHERE \(reference) = ?", arguments: [name, Int64(Date().timeIntervalSince1970 * 1000), original.name])
                }
                if kind == .category { try db.execute(sql: "UPDATE categories SET \"group\" = ? WHERE id = ?", arguments: [group.rawValue, original.id]) }
                if kind == .category, let semantic { try db.execute(sql: "UPDATE categories SET categorySemantic = ? WHERE id = ?", arguments: [semantic.rawValue, original.id]) }
            } else {
                let now = Int64(Date().timeIntervalSince1970 * 1000)
                if kind == .category {
                    try db.execute(sql: "INSERT INTO categories(name, \"group\", isPreset, createdAt) VALUES (?, ?, 0, ?)", arguments: [name, group.rawValue, now])
                    if let semantic { try db.execute(sql: "UPDATE categories SET categorySemantic = ? WHERE id = ?", arguments: [semantic.rawValue, db.lastInsertedRowID]) }
                } else {
                    try db.execute(sql: "INSERT INTO \(kind.table)(name, isPreset, createdAt) VALUES (?, 0, ?)", arguments: [name, now])
                }
            }
        }
        if kind == .brand, removeLogo, let path = original?.logoUrl { try? ImageFileHelper.deleteUnreferenced(paths: [path], db: queue) }
    }

    func delete(kind: AttributeKind, row: AttributeRow) async throws {
        try await queue.write { db in
            if kind == .season {
                try SeasonRepository.rewriteItemReferences(in: db, oldName: row.name, newName: nil)
            } else if let reference = kind.reference {
                try db.execute(sql: "UPDATE items SET \(reference) = NULL, updatedAt = ? WHERE \(reference) = ?", arguments: [Int64(Date().timeIntervalSince1970 * 1000), row.name])
            }
            try db.execute(sql: "DELETE FROM \(kind.table) WHERE id = ?", arguments: [row.id])
        }
    }
}

struct AttributeManageScreen: View {
    let kind: AttributeKind
    @StateObject private var vm = AttributeManageViewModel()
    @State private var editorTarget: AttributeEditorTarget?
    @State private var name = ""
    @State private var group: CategoryGroup = .clothing
    @State private var semantic: CategorySemantic = .unconfirmed
    @State private var error: String?
    @State private var search = ""
    @State private var removeLogo = false

    var body: some View {
        List {
            ForEach(vm.rows.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { row in
                Button {
                    name = row.name; group = row.group ?? .clothing; semantic = row.semantic; removeLogo = false; editorTarget = AttributeEditorTarget(row: row)
                } label: {
                    HStack {
                        if let path = row.logoUrl { LolitaShimmerImage(url: ImageFileHelper.fileURL(for: path), contentMode: .fit).frame(width: 44, height: 44) }
                        Text(row.name).foregroundStyle(.primary); Spacer(); SkinIcon(systemName: "pencil").foregroundStyle(.secondary)
                    }
                }
                .swipeActions {
                    Button("删除", role: .destructive) {
                        Task { do { try await vm.delete(kind: kind, row: row) } catch { self.error = userFacingError(error) } }
                    }
                }
            }
        }
        .searchable(text: $search, placement: attributeSearchPlacement, prompt: "搜索\(kind.rawValue)")
        .lolitaNavBar(title: "\(kind.rawValue)管理", showBack: true)
        .toolbar { ToolbarItem { Button("添加") { name = ""; group = .clothing; semantic = .unconfirmed; removeLogo = false; editorTarget = AttributeEditorTarget(row: nil) } } }
        .sheet(item: $editorTarget) { target in
            let editing = target.row
            NavigationStack {
                Form {
                    TextField("名称", text: $name)
                    if kind == .brand, let path = editing?.logoUrl, !removeLogo {
                        LolitaShimmerImage(url: ImageFileHelper.fileURL(for: path), contentMode: .fit).frame(height: 160)
                        Button("移除品牌图片", role: .destructive) { removeLogo = true }
                    }
                    if kind == .category {
                        Picker("稳定品类", selection: $semantic) { ForEach(CategorySemantic.allCases, id: \.self) { Text($0.label).tag($0) } }
                        Text("显示名称可以修改；稳定品类决定专属规格，重命名不会自动改类型。").font(.caption).foregroundStyle(.secondary)
                        Picker("分组", selection: $group) { Text("服装").tag(CategoryGroup.clothing); Text("配饰").tag(CategoryGroup.accessory) }
                    }
                }
                .navigationTitle(editing == nil ? "新增\(kind.rawValue)" : "编辑\(kind.rawValue)")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { editorTarget = nil } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            Task {
                                do { try await vm.save(kind: kind, original: editing, name: name, group: group, semantic: kind == .category ? semantic : nil, removeLogo: removeLogo); editorTarget = nil }
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
        .alert("操作失败", isPresented: Binding(get: { error != nil && editorTarget == nil }, set: { if !$0 { error = nil } })) {
            Button("确定") { error = nil }
        } message: { Text(error ?? "") }
        .task { await vm.observe(kind: kind) }
    }
    private var attributeSearchPlacement: SearchFieldPlacement {
        #if os(iOS)
        .navigationBarDrawer(displayMode: .always)
        #else
        .automatic
        #endif
    }
}

private struct AttributeEditorTarget: Identifiable {
    let row: AttributeRow?
    var id: String { row.map { "edit-\($0.id)" } ?? "new" }
}

struct LocationManageScreen: View {
    @State private var locations: [Location] = []
    @State private var deleting: Location?
    @State private var error: String?
    var body: some View {
        List(locations, id: \.id) { location in
            NavigationLink(location.name) { LocationDetailScreen(locationId: location.id) }
                .swipeActions {
                    Button("删除", role: .destructive) {
                        deleting = location
                    }
                }
        }
        .confirmationDialog("删除房间及全部下级收纳位置？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("删除位置，物品移至未设置", role: .destructive) {
                guard let location = deleting else { return }
                Task { do { try await AppModule.shared.locationRepository.delete(location, clearContents: true); deleting = nil } catch { self.error = userFacingError(error) } }
            }
        } message: { Text("物品、账本和照片都会保留，只清除存放位置。") }
        .lolitaNavBar(title: "位置管理", showBack: true)
        .toolbar { ToolbarItem { NavigationLink(destination: LocationEditScreen()) { SkinIcon(systemName: "plus") } } }
        .task { for await value in AppModule.shared.locationRepository.observeAll() { locations = value } }
        .alert("操作失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("确定") { error = nil } } message: { Text(error ?? "") }
    }
}
