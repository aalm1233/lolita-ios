import SwiftUI
@preconcurrency import GRDB

@MainActor
final class LookBuilderViewModel: ObservableObject {
    @Published private(set) var target: Item?
    @Published private(set) var groups: [LookGroup] = []
    @Published private(set) var selection = LookSelection()
    @Published private(set) var loading = false
    @Published private(set) var saving = false
    @Published private(set) var saved: Coordinate?
    @Published var error: String?
    private let repository: LookRepository
    init(db: DatabaseQueue = AppModule.shared.db.dbQueue) { repository = LookRepository(db: db) }
    var items: [Item] { (target.map { [$0] } ?? []) + groups.compactMap { group in group.options.first { $0.item.id == selection.selected[group.id] }?.item } }
    func load(_ id: Int64, force: Bool = false) async {
        guard !saving, !loading, force || target == nil else { return }
        loading = true; error = nil
        defer { loading = false }
        do {
            let (target, groups) = try await repository.load(itemId: id)
            try Task.checkCancellation()
            self.target = target; self.groups = groups; selection = LookSelection(groups: groups)
        } catch { if !Task.isCancelled { self.error = userFacingError(error) } }
    }
    func choose(_ slot: String, id: Int64?) {
        guard !loading, !saving, saved == nil, let group = groups.first(where: { $0.id == slot }), id == nil || group.options.contains(where: { $0.item.id == id }) else { return }
        selection.selected[slot] = id
    }
    func lock(_ slot: String) {
        guard !loading, !saving, saved == nil, selection.selected[slot] != nil else { return }
        if selection.locked.contains(slot) { selection.locked.remove(slot) } else { selection.locked.insert(slot) }
    }
    func shuffle() { guard !loading, !saving, saved == nil else { return }; selection.next(groups: groups) }
    func save(_ name: String) async -> Bool {
        guard !loading, !saving, target != nil, saved == nil else { return false }
        let snapshot = items
        saving = true; error = nil
        defer { saving = false }
        do { saved = try await repository.save(name: name, reviewed: snapshot); return true }
        catch { self.error = userFacingError(error); return false }
    }
}

struct LookBuilderScreen: View {
    let itemId: Int64
    @StateObject private var vm = LookBuilderViewModel()
    @State private var picker: String?
    @State private var showSave = false
    @State private var showDetail = false
    @State private var name = ""
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if vm.loading { ProgressView("正在生成搭配…") }
                if let error = vm.error, !showSave {
                    Text(error).foregroundStyle(.red)
                    Button("刷新搭配") { Task { await vm.load(itemId, force: true) } }
                }
                if let target = vm.target {
                    LolitaSection(title: "固定单品") { lookItem(target) }
                    Text("锁定喜欢的单品，再换一套；不需要的类型可以跳过。")
                        .font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    if vm.groups.isEmpty { Text("暂时没有可补齐的服饰，也可以把主件保存为套装。") }
                    ForEach(vm.groups) { group in slot(group) }
                }
            }.padding(16)
        }
        .lolitaNavBar(title: "整套搭配", showBack: true)
        .task { await vm.load(itemId) }
        .safeAreaInset(edge: .bottom) {
            if vm.target != nil {
                HStack {
                    Button("换一套") { vm.shuffle() }.buttonStyle(.bordered).accessibilityIdentifier("look-shuffle")
                    Button(vm.saved == nil ? "保存为套装" : "查看已保存套装") { if vm.saved == nil { showSave = true } else { showDetail = true } }
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("look-save")
                }.padding(12).frame(maxWidth: .infinity).background(.regularMaterial)
                    .disabled(vm.saving || vm.loading)
            }
        }
        .sheet(isPresented: Binding(get: { picker != nil }, set: { if !$0 { picker = nil } })) {
            if let slot = picker, let group = vm.groups.first(where: { $0.id == slot }) {
                LookOptionPicker(group: group) { vm.choose(slot, id: $0); picker = nil }
            }
        }
        .sheet(isPresented: $showSave) {
            NavigationStack {
                Form {
                    TextField("套装名称", text: $name).accessibilityIdentifier("look-name")
                    let moved = vm.items.filter { $0.coordinateId != nil }
                    if moved.isEmpty { Text("保存 \(vm.items.count) 件服饰为新套装。") }
                    else { Text("以下服饰已属于其他套装，保存会将它们移入新套装：\(moved.map(\.name).joined(separator: "、"))。原套装和照片会保留。") }
                    if let error = vm.error {
                        Text(error).foregroundStyle(.red)
                        Button("刷新后重新选择") { showSave = false; Task { await vm.load(itemId, force: true) } }
                    }
                }
                .lolitaNavBar(title: "保存为套装")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { showSave = false }.disabled(vm.saving) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("确认保存") {
                            let snapshot = name
                            Task { if await vm.save(snapshot) { showSave = false; showDetail = true } }
                        }.disabled(vm.saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("look-confirm")
                    }
                }
                .interactiveDismissDisabled(vm.saving)
            }
        }
        .navigationDestination(isPresented: $showDetail) { if let saved = vm.saved { CoordinateDetailScreen(coordinateId: saved.id) } }
    }
    private func slot(_ group: LookGroup) -> some View {
        LolitaSection(title: group.id, actionLabel: "替换", onAction: { picker = group.id }, actionIdentifier: "look-replace-" + group.id) {
            if let option = group.options.first(where: { $0.item.id == vm.selection.selected[group.id] }) {
                lookItem(option.item).accessibilityIdentifier("look-selected-" + group.id)
                Text(option.reasons.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                ViewThatFits(in: .horizontal) {
                    HStack { lockButton(group.id); Spacer(); skipButton(group.id) }
                    VStack(alignment: .leading) { lockButton(group.id); skipButton(group.id) }
                }
            } else { Text("已跳过").foregroundStyle(.secondary).accessibilityIdentifier("look-skipped-" + group.id) }
        }.disabled(vm.saving || vm.saved != nil)
    }
    private func lockButton(_ slot: String) -> some View {
        Toggle("锁定这件", isOn: Binding(get: { vm.selection.locked.contains(slot) }, set: { _ in vm.lock(slot) }))
            .toggleStyle(.switch).accessibilityIdentifier("look-lock-" + slot)
    }
    private func skipButton(_ slot: String) -> some View {
        Button("跳过") { vm.choose(slot, id: nil) }.accessibilityIdentifier("look-skip-" + slot)
    }
    private func lookItem(_ item: Item) -> some View {
        HStack(spacing: 12) {
            LolitaThumbnail(path: item.imageUrls.values.first, symbol: "hanger", width: 64, height: 80)
            Text(item.name).font(.body).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct LookOptionPicker: View {
    let group: LookGroup
    let choose: (Int64?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    var body: some View {
        NavigationStack {
            List {
                Button("跳过这个分类") { choose(nil) }
                ForEach(group.options.filter { search.isEmpty || $0.item.name.localizedCaseInsensitiveContains(search) }, id: \.item.id) { option in
                    Button { choose(option.item.id) } label: {
                        HStack {
                            LolitaThumbnail(path: option.item.imageUrls.values.first, symbol: "hanger", width: 40, height: 50)
                            Text(option.item.name).foregroundStyle(.primary)
                        }
                    }.accessibilityIdentifier("look-option-\(option.item.id)")
                }
            }.searchable(text: $search, prompt: "搜索服饰名称")
                .lolitaNavBar(title: "选择\(group.id)")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
    }
}
