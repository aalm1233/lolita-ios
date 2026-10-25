import SwiftUI
#if canImport(PhotosUI)
import PhotosUI
#endif

struct LocationEditScreen: View {
    @State private var saveError: String?
    @StateObject private var viewModel: LocationEditViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var skinManager: SkinManager
    @State private var showCancelAlert = false
    @State private var isSubmitting = false
    @State private var isImportingImage = false
    @State private var showBuiltInArtwork = false

    #if os(iOS)
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var imageImportTask: Task<Void, Never>?
    @State private var imageImportId: UUID?
    #endif

    private var isBusy: Bool { isSubmitting || viewModel.isSaving }

    let onSave: (() async -> Void)?

    init(locationId: Int64 = 0, onSave: (() async -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: LocationEditViewModel(locationId: locationId))
        self.onSave = onSave
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Image picker section
                VStack(alignment: .leading, spacing: 8) {
                    Text("图片")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if let imageUrl = viewModel.imageUrl {
                        ZStack {
                            Color.clear
                            LolitaShimmerImage(url: ImageFileHelper.fileURL(for: imageUrl))
                        }
                            .frame(maxWidth: .infinity)
                            .frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: skinManager.current.cornerRadiusM))

                        Button("移除图片", role: .destructive) {
                            viewModel.removeImage()
                        }
                        .font(.subheadline)
                        .disabled(isImportingImage)
                    } else {
                        RoundedRectangle(cornerRadius: skinManager.current.cornerRadiusM)
                            .fill(Color.gray.opacity(0.1))
                            .frame(height: 200)
                            .overlay {
                                SkinIcon(systemName: "photo.badge.plus", size: 34)
                                    .foregroundStyle(.secondary)
                            }
                    }

                    #if os(iOS)
                    let showsImportProgress = isImportingImage
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        HStack {
                            SkinLabel("选择图片", systemImage: "photo.on.rectangle")
                                .font(.subheadline)
                            if showsImportProgress { ProgressView() }
                        }
                    }
                    .disabled(isImportingImage)
                    #endif
                    Button("使用房间示意图") { showBuiltInArtwork = true }
                        .disabled(isImportingImage)
                        .accessibilityIdentifier("choose-builtin-room")
                }

                // Name field
                LolitaCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("名称")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("位置名称", text: $viewModel.name)
                            .textFieldStyle(.plain)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Description field
                LolitaCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("描述")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("补充位置或收纳说明", text: $viewModel.description, axis: .vertical)
                            .lineLimit(3...6)
                            .textFieldStyle(.plain)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .disabled(isBusy)
        .sheet(isPresented: $showBuiltInArtwork) {
            BuiltInRoomArtworkScreen { room in
                let image = try BuiltInLibrary.copyImage(room.assetPath)
                viewModel.removeImage()
                viewModel.imageUrl = image
                if viewModel.name.isEmpty { viewModel.name = room.name }
                if viewModel.description.isEmpty { viewModel.description = room.description }
            }
        }
        .interactiveDismissDisabled(isBusy || isImportingImage || viewModel.hasChanges)
        .onDisappear {
            #if os(iOS)
            imageImportTask?.cancel()
            imageImportTask = nil
            imageImportId = nil
            selectedItem = nil
            #endif
            isImportingImage = false
        }
        .alert("保存失败", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("确定", role: .cancel) { saveError = nil }
        } message: { Text(saveError ?? "") }
        .lolitaNavBar(title: viewModel.locationId == 0 ? "新增位置" : "编辑位置", showBack: true, onBack: {
            guard !isBusy else { return }
            if viewModel.hasChanges { showCancelAlert = true }
            else { discardAndDismiss() }
        })
        #if os(iOS)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("保存") {
                    guard !isBusy, !isImportingImage else { return }
                    isSubmitting = true
                    Task {
                        defer { isSubmitting = false }
                        do {
                            try await viewModel.save()
                            await onSave?()
                            dismiss()
                        } catch { saveError = userFacingError(error) }
                    }
                }
                .fontWeight(.semibold)
                .disabled(isBusy || isImportingImage || viewModel.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        #endif
        .alert("放弃更改？", isPresented: $showCancelAlert) {
            Button("放弃", role: .destructive) {
                guard !isBusy else { return }
                discardAndDismiss()
            }
            .disabled(isBusy)
            Button("继续编辑", role: .cancel) {}
        } message: {
            Text("未保存的更改将丢失。")
        }
        #if os(iOS)
        .onChange(of: selectedItem) { _, newItem in
            imageImportTask?.cancel()
            imageImportTask = nil
            imageImportId = nil
            guard !isBusy, let item = newItem else { isImportingImage = false; return }
            let importId = UUID()
            imageImportId = importId
            isImportingImage = true
            imageImportTask = Task { @MainActor in
                defer {
                    if imageImportId == importId {
                        isImportingImage = false
                        imageImportTask = nil
                        imageImportId = nil
                        selectedItem = nil
                    }
                }
                do {
                    let data = try await item.loadTransferable(type: Data.self)
                    guard !Task.isCancelled, imageImportId == importId, !isBusy else { return }
                    guard let data else { saveError = "无法读取图片，请重新选择。"; return }
                    viewModel.setImage(data: data)
                } catch {
                    guard !Task.isCancelled, imageImportId == importId else { return }
                    saveError = "图片读取失败，请重新选择。"
                }
            }
        }
        #endif
        .task { await viewModel.load() }
    }

    private func discardAndDismiss() {
        #if os(iOS)
        imageImportTask?.cancel()
        imageImportTask = nil
        imageImportId = nil
        selectedItem = nil
        #endif
        isImportingImage = false
        viewModel.discardImages()
        dismiss()
    }
}
