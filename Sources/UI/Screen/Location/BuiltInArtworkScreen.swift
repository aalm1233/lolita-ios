import SwiftUI

struct BuiltInRoomArtworkScreen: View {
    let onSelect: (BuiltInLibrary.Room) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var rooms: [BuiltInLibrary.Room] = []
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 16) {
                    ForEach(rooms, id: \.name) { room in
                        Button {
                            do { try onSelect(room); dismiss() } catch { self.error = userFacingError(error) }
                        } label: {
                            VStack {
                                LolitaShimmerImage(url: try? BuiltInLibrary.assetURL(room.assetPath), contentMode: .fit).frame(height: 140)
                                Text(room.name).foregroundStyle(.primary)
                            }.padding(8)
                        }.buttonStyle(.plain).accessibilityIdentifier("builtin-room-\(room.name)")
                    }
                }.padding()
            }.navigationTitle("房间示意图")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
                .task { do { rooms = try BuiltInLibrary.catalog().rooms } catch { self.error = userFacingError(error) } }
                .alert("无法读取示意图", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("确定") { error = nil } } message: { Text(error ?? "") }
        }
    }
}

struct BuiltInStorageTemplateScreen: View {
    let roomId: Int64
    @Environment(\.dismiss) private var dismiss
    @State private var templates: [BuiltInLibrary.StorageTemplate] = []
    @State private var selected = Set<String>()
    @State private var error: String?
    @State private var isSaving = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("选择示意图，在当前房间添加柜架。添加后可编辑名称、照片和下级层格。").font(.subheadline).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 16) {
                        ForEach(templates) { template in
                            Button {
                                if !selected.insert(template.id).inserted { selected.remove(template.id) }
                            } label: {
                                VStack {
                                    LolitaShimmerImage(url: try? BuiltInLibrary.assetURL(template.assetPath), contentMode: .fit).frame(height: 140)
                                    HStack {
                                        Text(template.name).foregroundStyle(.primary)
                                        SkinIcon(systemName: selected.contains(template.id) ? "checkmark.circle.fill" : "circle")
                                    }
                                }.padding(8)
                            }.buttonStyle(.plain).accessibilityIdentifier("builtin-storage-\(template.id)")
                                .accessibilityValue(selected.contains(template.id) ? "已选择" : "未选择")
                        }
                    }
                }.padding()
            }.disabled(isSaving)
                .navigationTitle("收纳示意图")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(isSaving) } }
                .safeAreaInset(edge: .bottom) {
                    LolitaEditorSaveBar(title: "添加所选柜架（\(selected.count)）", enabled: !selected.isEmpty && !isSaving, identifier: "builtin-adopt-storage") {
                        isSaving = true
                        do { try BuiltInLibrary.adoptTemplates(selected, roomId: roomId, db: AppModule.shared.db.dbQueue); dismiss() }
                        catch { self.error = userFacingError(error); isSaving = false }
                    }
                }
                .interactiveDismissDisabled(isSaving)
                .task { do { templates = try BuiltInLibrary.templates() } catch { self.error = userFacingError(error) } }
                .alert("无法添加柜架", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("确定") { error = nil } } message: { Text(error ?? "") }
        }
    }
}
