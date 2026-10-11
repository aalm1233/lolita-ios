import SwiftUI
#if os(iOS)
import PhotosUI
import UIKit
#endif

struct QuickOutfitLogScreen: View {
    @State private var saveError: String?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var skinManager: SkinManager
    @StateObject private var viewModel = QuickOutfitLogViewModel()

    #if os(iOS)
    @State private var photoPickerItems: [PhotosPickerItem] = []
    #endif

    var body: some View {
        #if os(iOS)
        let hasNewImage = viewModel.newImage != nil
        #endif
        Form {
            Section {
                TextField("备注", text: $viewModel.note)
                    .lineLimit(4)
            } header: {
                Text("记录")
            }

            Section {
                #if os(iOS)
                PhotosPicker(selection: $photoPickerItems,
                             maxSelectionCount: 1,
                             matching: .images) {
                    if hasNewImage {
                        Label("已选择图片", systemImage: "photo.fill")
                            .foregroundStyle(.secondary)
                    } else {
                        Label("添加图片", systemImage: "photo.badge.plus")
                    }
                }
                .onChange(of: photoPickerItems) { _, newItems in
                    Task {
                        guard let item = newItems.first,
                              let data = try? await item.loadTransferable(type: Data.self),
                              let uiImage = UIImage(data: data) else { return }
                        viewModel.newImage = uiImage
                    }
                }
                #else
                Label("macOS 暂不支持添加图片", systemImage: "photo.badge.plus")
                    .foregroundStyle(.secondary)
                #endif
            } header: {
                Text("图片")
            }

            Section {
                if viewModel.ownedItems.isEmpty {
                    Text("暂无可用服饰")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.ownedItems, id: \.id) { item in
                        Button(action: {
                            if viewModel.selectedItemIds.contains(item.id) {
                                viewModel.selectedItemIds.remove(item.id)
                            } else {
                                viewModel.selectedItemIds.insert(item.id)
                            }
                        }) {
                            HStack {
                                ItemRow(item: item)
                                Spacer()
                                if viewModel.selectedItemIds.contains(item.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(skinManager.current.accentColor)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("关联服饰")
            }
        }
        .onDisappear { viewModel.discardImages() }
        .alert("保存失败", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("确定", role: .cancel) { saveError = nil }
        } message: { Text(saveError ?? "") }
        .lolitaNavBar(title: "快速记录", showBack: true)
#if os(iOS)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("保存") {
                    Task {
                        do {
                            try await viewModel.save()
                            dismiss()
                        } catch { saveError = userFacingError(error) }
                    }
                }
            }
        }
#endif
        .onAppear { viewModel.loadItems() }
    }
}
