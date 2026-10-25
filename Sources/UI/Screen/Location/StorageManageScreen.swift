import SwiftUI

struct StorageManageScreen: View {
    let roomId: Int64
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var rooms: [Location] = []
    @State private var nodes: [StorageNode] = []
    @State private var editorTarget: StorageEditorTarget?
    @State private var moving: StorageNode?
    @State private var assigning: StorageNode?
    @State private var deleting: StorageNode?
    @State private var error: String?
    @State private var showTemplates = false
    @State private var reload = 0
    private var repository: StorageRepository { StorageRepository(db: AppModule.shared.db.dbQueue) }
    var body: some View {
        List {
            Section("房间 → 柜架 → 层格") {
                Button("从示意图添加柜架") { showTemplates = true }.accessibilityIdentifier("choose-builtin-storage")
                Text("移动柜架会同步移动下级层格、物品与编辑草稿；物品和照片均会保留。")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(nodes.filter { $0.locationId == roomId }, id: \.id) { node in
                    nodeRow(node)
                }
                if !nodes.contains(where: { $0.locationId == roomId }) { Text("还没有柜架，点击右上角添加。").foregroundStyle(.secondary) }
            }
        }
        .lolitaNavBar(title: "分层收纳", showBack: true)
        .toolbar { ToolbarItem { Button("添加柜架／层格") { editorTarget = StorageEditorTarget(node: nil) }.accessibilityIdentifier("add-storage-node") } }
        .task(id: reload) {
            do { rooms = try await AppModule.shared.locationRepository.getAll(); nodes = try await repository.getAll() }
            catch { self.error = userFacingError(error) }
        }
        .sheet(item: $editorTarget, onDismiss: { reload += 1 }) { target in StorageNodeEditor(roomId: roomId, node: target.node, nodes: nodes).id(target.id) }
        .sheet(isPresented: $showTemplates, onDismiss: { reload += 1 }) { BuiltInStorageTemplateScreen(roomId: roomId) }
        .sheet(item: $moving, onDismiss: { reload += 1 }) { node in StorageNodeMoveScreen(node: node, rooms: rooms, nodes: nodes).id(node.id) }
        .sheet(item: $assigning, onDismiss: { reload += 1 }) { node in StorageMembershipScreen(node: node).id(node.id) }
        .confirmationDialog("删除位置及下级位置？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("删除位置，物品移至未设置", role: .destructive) {
                guard let node = deleting else { return }
                Task { do { try await repository.delete(nodeId: node.id, clearContents: true); deleting = nil; reload += 1 } catch { self.error = userFacingError(error) } }
            }
        } message: { Text("物品、账本和照片会保留，只清除存放位置。") }
        .alert("操作失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("确定") { error = nil } } message: { Text(error ?? "") }
    }
    private var actionLayout: AnyLayout { dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8)) }
    private func nodeRow(_ node: StorageNode) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let image = node.imageUrl { LolitaShimmerImage(url: ImageFileHelper.fileURL(for: image), contentMode: .fit).frame(height: 150) }
            Text(StorageTree.path(roomId: roomId, nodeId: node.id, rooms: rooms, nodes: nodes)).font(.headline)
            if !node.description.isEmpty { Text(node.description).font(.caption) }
            actionLayout {
                Button("编辑") { editorTarget = StorageEditorTarget(node: node) }.buttonStyle(.bordered).accessibilityIdentifier("edit-node-\(node.id)")
                Button("移动") { moving = node }.buttonStyle(.bordered).accessibilityIdentifier("move-node-\(node.id)")
                Button("放入物品") { assigning = node }.buttonStyle(.bordered).accessibilityIdentifier("assign-node-\(node.id)")
            }
        }.padding(.vertical, 6)
        .swipeActions { Button("删除", role: .destructive) { deleting = node } }
    }

}

private struct StorageEditorTarget: Identifiable {
    let node: StorageNode?
    var id: String { node.map { "edit-\($0.id)" } ?? "new" }
}

private struct StorageNodeEditor: View {
    let roomId: Int64
    let node: StorageNode?
    let nodes: [StorageNode]
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var parentId: Int64?
    @State private var photos: [String] = []
    @State private var isSaving = false
    @State private var isImporting = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("收纳位置") {
                    TextField("收纳名称（必填）", text: $name).accessibilityIdentifier("storage-name")
                    TextField("收纳说明", text: $description)
                    if node == nil {
                        Picker("上级柜架", selection: $parentId) {
                            Text("房间（新增柜架）").tag(nil as Int64?)
                            ForEach(nodes.filter { $0.locationId == roomId && $0.parentNodeId == nil }, id: \.id) { Text($0.name).tag($0.id as Int64?) }
                        }.accessibilityIdentifier("storage-parent")
                    }
                }
                EditPhotosSection(title: "位置照片", imageUrls: photos, onAddData: { data in
                    if let path = ImageFileHelper.save(imageData: data) { photos.append(path) }
                }, onRemove: { index in
                    let path = photos.remove(at: index)
                    if path != node?.imageUrl { try? AppModule.shared.locationRepository.cleanupImages([path]) }
                }, onImportingChanged: { isImporting = $0 })
                if photos.count > 1 { Text("位置只保留第一张照片；多余图片会在保存后清理。").font(.caption) }
            }.scrollDismissesKeyboard(.interactively).disabled(isSaving)
            .navigationTitle(node == nil ? "新增收纳位置" : "编辑收纳位置")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { cleanup(); dismiss() }.disabled(isSaving) } }
            .safeAreaInset(edge: .bottom) {
                LolitaEditorSaveBar(title: "保存位置", enabled: !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving && !isImporting, identifier: "storage-save") {
                    saveNode()
                }
            }
            .interactiveDismissDisabled(true)
            .onAppear { name = node?.name ?? ""; description = node?.description ?? ""; parentId = node?.parentNodeId; photos = [node?.imageUrl].compactMap { $0 } }
            .alert("保存失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("确定") { error = nil } } message: { Text(error ?? "") }
        }
    }
    private func saveNode() {
        var value = node ?? StorageNode(locationId: roomId, parentNodeId: parentId, name: name)
        value.name = name; value.description = description; value.imageUrl = photos.first
        let submitted = value
        let cleanupPaths = photos + [node?.imageUrl].compactMap { $0 }
        isSaving = true
        Task {
            do {
                _ = try await StorageRepository(db: AppModule.shared.db.dbQueue).save(submitted)
                try? AppModule.shared.locationRepository.cleanupImages(cleanupPaths)
                dismiss()
            } catch { self.error = userFacingError(error); isSaving = false }
        }
    }
    private func cleanup() { try? AppModule.shared.locationRepository.cleanupImages(photos.filter { $0 != node?.imageUrl }) }
}

private struct StorageNodeMoveScreen: View {
    let node: StorageNode
    let rooms: [Location]
    let nodes: [StorageNode]
    @Environment(\.dismiss) private var dismiss
    @State private var roomId: Int64?
    @State private var parentId: Int64?
    @State private var isSaving = false
    @State private var error: String?
    init(node: StorageNode, rooms: [Location], nodes: [StorageNode]) {
        self.node = node; self.rooms = rooms; self.nodes = nodes
        _roomId = State(initialValue: node.locationId); _parentId = State(initialValue: node.parentNodeId)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("移动位置") {
                    Text(node.name)
                    StoragePlacementPicker(rooms: rooms, nodes: nodes.filter { !StorageTree.descendants(node.id, nodes: nodes).contains($0.id) && $0.parentNodeId == nil }, roomId: $roomId, nodeId: $parentId)
                    Text("下级位置与其中的物品、草稿会一起移动，不改变物品和图片。")
                }
            }
            .navigationTitle("移动收纳位置")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(isSaving) } }
            .safeAreaInset(edge: .bottom) {
                LolitaEditorSaveBar(title: "确认移动", enabled: roomId != nil && !isSaving, identifier: "storage-move-save") {
                    guard let destination = roomId else { return }
                    let parent = parentId; isSaving = true
                    Task { do { try await StorageRepository(db: AppModule.shared.db.dbQueue).move(nodeId: node.id, roomId: destination, parentId: parent); dismiss() } catch { self.error = userFacingError(error); isSaving = false } }
                }
            }
            .interactiveDismissDisabled(isSaving)
            .alert("移动失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("确定") { error = nil } } message: { Text(error ?? "") }
        }
    }
}

private struct StorageMembershipScreen: View {
    let node: StorageNode
    @Environment(\.dismiss) private var dismiss
    @State private var items: [Item] = []
    @State private var original: Set<Int64> = []
    @State private var selected: Set<Int64> = []
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                Text("仅已拥有物品可以放入；取消勾选会移至未设置位置。").font(.caption).foregroundStyle(.secondary)
                if isLoading { ProgressView("正在读取收纳物品") }
                ForEach(items.filter { $0.status == .owned || original.contains($0.id) }, id: \.id) { item in
                    Button {
                        if !selected.insert(item.id).inserted { selected.remove(item.id) }
                    } label: {
                        HStack { Text(item.name).foregroundStyle(.primary); Spacer(); SkinIcon(systemName: selected.contains(item.id) ? "checkmark.circle.fill" : "circle") }
                    }.accessibilityIdentifier("storage-item-\(item.id)")
                    .accessibilityValue(selected.contains(item.id) ? "已选择" : "未选择")
                }
            }.navigationTitle("放入物品").disabled(isSaving || isLoading)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(isSaving) } }
            .safeAreaInset(edge: .bottom) {
                LolitaEditorSaveBar(title: "保存收纳", enabled: !isSaving && !isLoading, identifier: "storage-members-save") {
                    let ids = selected, baseline = original; isSaving = true
                    Task { do { try await StorageRepository(db: AppModule.shared.db.dbQueue).setMembership(nodeId: node.id, originalIds: baseline, selectedIds: ids); dismiss() } catch { self.error = userFacingError(error); isSaving = false } }
                }
            }
            .task(id: node.id) {
                isLoading = true; items = []; original = []; selected = []
                let requestedNodeId = node.id
                do {
                    let loaded = try await AppModule.shared.itemRepository.getAll()
                    guard !Task.isCancelled else { return }
                    items = loaded
                    original = Set(loaded.filter { $0.storageNodeId == requestedNodeId }.map(\.id))
                    selected = original
                    isLoading = false
                } catch { if !Task.isCancelled { self.error = userFacingError(error) } }
            }
            .interactiveDismissDisabled(isSaving)
            .alert("保存失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("确定") { error = nil } } message: { Text(error ?? "") }
        }
    }
}
