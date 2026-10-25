import SwiftUI

struct CoordinateEditScreen: View {
    @State private var showDiscard = false
    @State private var showItemPicker = false
    @State private var saveError: String?
    @State private var isImportingPhotos = false
    @State private var isLeaving = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var skinManager: SkinManager
    @StateObject private var viewModel = CoordinateEditViewModel()

    var coordinateId: Int64 = 0

    private var cardBackground: Color {
        colorScheme == .dark ? skinManager.current.cardColorDark : skinManager.current.cardColor
    }

    private var availableItems: [Item] {
        viewModel.allItems.filter {
            viewModel.selectedItemIds.contains($0.id) || $0.coordinateId == nil || $0.coordinateId == coordinateId
        }
    }

    var body: some View {
        Form {
            EditPhotosSection(
                title: "套装照片",
                imageUrls: viewModel.imageUrls,
                showsCoverLabel: true,
                aspectRatio: 1,
                onAddData: { data in
                    guard !isLeaving else { return }
                    viewModel.addImageData(data)
                },
                onRemove: viewModel.removeImage,
                onImportingChanged: { isImportingPhotos = $0 }
            )

            Section {
                TextField("套装名称（必填）", text: $viewModel.name)
                TextField("搭配灵感、描述（选填）", text: $viewModel.description, axis: .vertical)
                    .lineLimit(2...5)
            } header: {
                Text("基本信息")
            }
            .lolitaCollectionRowInsets()
            .listRowBackground(cardBackground)

            Section {
                if viewModel.selectedItemIds.isEmpty {
                    Text("选择组成这套搭配的服饰")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(viewModel.selectedItemIds.enumerated()), id: \.element) { index, id in
                        if let item = viewModel.allItems.first(where: { $0.id == id }) {
                            EditSelectedItemRow(item: item, order: index + 1) { viewModel.toggleItem(id) }
                        }
                    }
                }
                Button { showItemPicker = true } label: {
                    SkinLabel("选择服饰", systemImage: "plus.circle")
                }
            } header: {
                Text("关联服饰 · \(viewModel.selectedItemIds.count) 件")
            } footer: {
                Text("按选择顺序展示，已归入其他套装的服饰不可重复选择")
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
                title: "选择套装服饰",
                items: availableItems,
                selectedIds: Set(viewModel.selectedItemIds),
                footer: "选择顺序就是套装中的展示顺序",
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
        .lolitaNavBar(title: coordinateId == 0 ? "新增套装" : "编辑套装", showBack: true, onBack: {
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
                .disabled(viewModel.name.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isSaving || isImportingPhotos)
            }
        }
        #endif
        .task { await viewModel.load(coordinateId: coordinateId) }
    }

    private func discardAndDismiss() {
        guard !viewModel.isSaving else { return }
        isLeaving = true
        viewModel.discardImages()
        dismiss()
    }
}
