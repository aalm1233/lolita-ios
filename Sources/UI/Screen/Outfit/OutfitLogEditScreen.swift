import SwiftUI

struct OutfitLogEditScreen: View {
    @State private var showDiscard = false
    @State private var showItemPicker = false
    @State private var saveError: String?
    @State private var isImportingPhotos = false
    @State private var isLeaving = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var skinManager: SkinManager
    @StateObject private var viewModel = OutfitLogEditViewModel()

    let logId: Int64

    private var cardBackground: Color {
        colorScheme == .dark ? skinManager.current.cardColorDark : skinManager.current.cardColor
    }

    var body: some View {
        Form {
            Section {
                DatePicker("日期", selection: $viewModel.date, displayedComponents: .date)
                TextField("场合、心情、穿着感受（选填）", text: $viewModel.note, axis: .vertical)
                    .lineLimit(2...5)
            } header: {
                Text("穿搭记录")
            }
            .lolitaCollectionRowInsets()
            .listRowBackground(cardBackground)

            EditPhotosSection(
                title: "穿搭照片",
                imageUrls: viewModel.imageUrls,
                onAddData: { data in
                    guard !isLeaving else { return }
                    viewModel.addImageData(data)
                },
                onRemove: viewModel.removeImage,
                onImportingChanged: { isImportingPhotos = $0 }
            )

            Section {
                if viewModel.selectedItemIds.isEmpty {
                    Text("记录今天穿了哪些服饰")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.allItems.filter { viewModel.selectedItemIds.contains($0.id) }, id: \.id) { item in
                        EditSelectedItemRow(item: item) { viewModel.toggleItem(item.id) }
                    }
                }
                Button { showItemPicker = true } label: {
                    Label("选择服饰", systemImage: "plus.circle")
                }
            } header: {
                Text("关联服饰 · \(viewModel.selectedItemIds.count) 件")
            }
            .lolitaCollectionRowInsets()
            .listRowBackground(cardBackground)
        }
        #if os(iOS)
        .contentMargins(.horizontal, 12, for: .scrollContent)
        #endif
        .disabled(viewModel.isSaving)
        .scrollDismissesKeyboard(.interactively)
        .interactiveDismissDisabled(viewModel.isSaving || viewModel.hasChanges || isImportingPhotos)
        .sheet(isPresented: $showItemPicker) {
            EditItemSelectionSheet(
                title: "选择穿搭服饰",
                items: viewModel.allItems,
                selectedIds: viewModel.selectedItemIds,
                onToggle: viewModel.toggleItem
            )
            .disabled(viewModel.isSaving)
            .interactiveDismissDisabled(viewModel.isSaving)
        }
        .confirmationDialog("放弃未保存的更改？", isPresented: $showDiscard, titleVisibility: .visible) {
            Button("放弃更改", role: .destructive) {
                guard !viewModel.isSaving else { return }
                discardAndDismiss()
            }
            .disabled(viewModel.isSaving)
            Button("继续编辑", role: .cancel) {}
        }
        .alert("保存失败", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("确定", role: .cancel) { saveError = nil }
        } message: { Text(saveError ?? "") }
        .lolitaNavBar(title: "编辑穿搭记录", showBack: true, onBack: {
            guard !viewModel.isSaving else { return }
            if viewModel.hasChanges || isImportingPhotos { showDiscard = true }
            else { discardAndDismiss() }
        })
#if os(iOS)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("保存") {
                    guard !viewModel.isSaving, !isImportingPhotos else { return }
                    Task {
                        do {
                            try await viewModel.save()
                            dismiss()
                        } catch { saveError = userFacingError(error) }
                    }
                }
                .disabled(viewModel.isSaving || isImportingPhotos)
            }
        }
#endif
        .task { await viewModel.load(logId: logId) }
    }

    private func discardAndDismiss() {
        guard !viewModel.isSaving else { return }
        isLeaving = true
        viewModel.discardImages()
        dismiss()
    }
}
