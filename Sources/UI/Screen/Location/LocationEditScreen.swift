import SwiftUI
#if canImport(PhotosUI)
import PhotosUI
#endif

struct LocationEditScreen: View {
    @StateObject private var viewModel: LocationEditViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var skin: DefaultSkin
    @State private var showCancelAlert = false

    #if os(iOS)
    @State private var selectedItem: PhotosPickerItem? = nil
    #endif

    let onSave: (() async -> Void)?

    init(locationId: Int64, onSave: (() async -> Void)? = nil) {
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
                        LolitaShimmerImage(url: ImageFileHelper.fileURL(for: imageUrl))
                            .frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: skin.cornerRadiusM))

                        Button("移除图片", role: .destructive) {
                            viewModel.removeImage()
                        }
                        .font(.subheadline)
                    } else {
                        RoundedRectangle(cornerRadius: skin.cornerRadiusM)
                            .fill(Color.gray.opacity(0.1))
                            .frame(height: 200)
                            .overlay {
                                Image(systemName: "photo.badge.plus")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                            }
                    }

                    #if os(iOS)
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        Label("选择图片", systemImage: "photo.on.rectangle")
                            .font(.subheadline)
                    }
                    #endif
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
                        TextField("描述", text: $viewModel.description)
                            .textFieldStyle(.plain)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .lolitaNavBar(title: "编辑位置", showBack: true, onBack: { showCancelAlert = true })
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("保存") {
                    Task {
                        try? await viewModel.save()
                        await onSave?()
                        dismiss()
                    }
                }
                .fontWeight(.semibold)
            }
        }
        #endif
        .alert("放弃更改？", isPresented: $showCancelAlert) {
            Button("放弃", role: .destructive) { dismiss() }
            Button("继续编辑", role: .cancel) {}
        } message: {
            Text("未保存的更改将丢失。")
        }
        #if os(iOS)
        .onChange(of: selectedItem) { _, newItem in
            Task {
                guard let item = newItem,
                      let data = try? await item.loadTransferable(type: Data.self) else { return }
                viewModel.setImage(data: data)
            }
        }
        #endif
        .task { await viewModel.load() }
    }
}
