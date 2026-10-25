import SwiftUI

struct QuickOutfitLogScreen: View {
    @FocusState private var noteFocused: Bool
    @State private var saveError: String?
    @State private var loadError: String?
    @State private var showDiscard = false
    @State private var showItemPicker = false
    @State private var isImportingPhotos = false
    @State private var isLeaving = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var skinManager: SkinManager
    @StateObject private var viewModel = QuickOutfitLogViewModel()

    private var isBusy: Bool { viewModel.isLoading || viewModel.isSaving }
    private var cardBackground: Color {
        colorScheme == .dark ? skinManager.current.cardColorDark : skinManager.current.cardColor
    }

    var body: some View {
        Form {
            Section {
                if viewModel.isLoading { ProgressView("正在加载今天的穿搭") }
                if let loadError {
                    Text(loadError).foregroundStyle(.secondary)
                    Button("重新加载") { Task { await load() } }
                } else {
                    Text(viewModel.existingLogId == nil ? "记录今天的穿搭" : "今天已有记录，保存将更新这条穿搭")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("场合、心情、穿着感受（选填）", text: $viewModel.note, axis: .vertical)
                        .lineLimit(2...5).focused($noteFocused).accessibilityIdentifier("quick-outfit-note")
                }
            } header: { Text("今日穿搭") }
            .lolitaCollectionRowInsets()
            .listRowBackground(cardBackground)

            EditPhotosSection(
                title: "穿搭照片", imageUrls: viewModel.imageUrls,
                onAddData: { data in
                    guard !isLeaving else { return }
                    viewModel.addImageData(data)
                },
                onRemove: viewModel.removeImage,
                onImportingChanged: { isImportingPhotos = $0 }
            )
            .disabled(!viewModel.hasLoaded)

            Section {
                if viewModel.selectedItems.isEmpty {
                    Text("请至少选择一件服饰")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.selectedItems, id: \.id) { item in
                        EditSelectedItemRow(item: item) { viewModel.toggleItem(item.id) }
                    }
                }
                Button { showItemPicker = true } label: {
                    SkinLabel("选择服饰", systemImage: "plus.circle")
                }
                .disabled(!viewModel.hasLoaded)
            } header: { Text("关联服饰 · \(viewModel.selectedItemIds.count) 件") }
            .lolitaCollectionRowInsets()
            .listRowBackground(cardBackground)
        }
        #if os(iOS)
        .contentMargins(.horizontal, 12, for: .scrollContent)
        #endif
        .disabled(isBusy)
        .scrollDismissesKeyboard(.interactively)
        .interactiveDismissDisabled(isBusy || viewModel.hasChanges || isImportingPhotos)
        .sheet(isPresented: $showItemPicker) {
            EditItemSelectionSheet(
                title: "选择今日穿搭服饰", items: viewModel.ownedItems,
                selectedIds: viewModel.selectedItemIds, onToggle: viewModel.toggleItem
            )
            .disabled(isBusy)
            .interactiveDismissDisabled(isBusy)
        }
        .confirmationDialog("放弃未保存的更改？", isPresented: $showDiscard, titleVisibility: .visible) {
            Button("放弃更改", role: .destructive) { discardAndDismiss() }
                .disabled(isBusy)
            Button("继续编辑", role: .cancel) {}
        }
        .alert("保存失败", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("确定", role: .cancel) { saveError = nil }
        } message: { Text(saveError ?? "") }
        .lolitaNavBar(title: "快速记录", showBack: true, onBack: {
            guard !isBusy else { return }
            if viewModel.hasChanges || isImportingPhotos { showDiscard = true }
            else { discardAndDismiss() }
        })
        #if os(iOS)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成输入") { noteFocused = false }.accessibilityIdentifier("quick-dismiss-keyboard")
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("保存今日穿搭（\(viewModel.selectedItemIds.count) 件）") {
                    guard !isBusy, !isImportingPhotos else { return }
                    Task {
                        do {
                            try await viewModel.save()
                            dismiss()
                        } catch { saveError = userFacingError(error) }
                    }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("quick-outfit-save")
                .disabled(isBusy || isImportingPhotos || !viewModel.hasLoaded)
            }.padding(12).frame(maxWidth: .infinity).background(.regularMaterial)
        }
        #endif
        .task { await load() }
    }

    private func load() async {
        do { try await viewModel.load(); loadError = nil }
        catch {
            guard !Task.isCancelled else { return }
            loadError = userFacingError(error)
        }
    }

    private func discardAndDismiss() {
        guard !isBusy else { return }
        isLeaving = true
        viewModel.discardImages()
        dismiss()
    }
}
