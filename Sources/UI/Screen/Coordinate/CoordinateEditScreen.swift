import SwiftUI
#if os(iOS)
import PhotosUI
#endif

struct CoordinateEditScreen: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var skin: DefaultSkin
    @StateObject private var viewModel = CoordinateEditViewModel()

    let coordinateId: Int64

    #if os(iOS)
    @State private var selectedItems: [PhotosPickerItem] = []
    #endif

    var body: some View {
        Form {
            Section {
                TextField("名称", text: $viewModel.name)
                TextField("描述", text: $viewModel.description)
                    .lineLimit(6)
            } header: {
                Text("基本信息")
            }

            Section {
                if !viewModel.imageUrls.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(viewModel.imageUrls.enumerated()), id: \.offset) { index, path in
                                ZStack(alignment: .topTrailing) {
                                    LolitaShimmerImage(url: ImageFileHelper.fileURL(for: path))
                                        .frame(width: 80, height: 80)
                                        .clipShape(RoundedRectangle(cornerRadius: skin.cornerRadiusS))

                                    Button(action: { viewModel.removeImage(at: index) }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 20))
                                            .foregroundStyle(.white, Color.red.opacity(0.8))
                                            .background(Circle().fill(.white).frame(width: 18, height: 18))
                                    }
                                    .offset(x: 6, y: -6)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                #if os(iOS)
                PhotosPicker(selection: $selectedItems,
                             maxSelectionCount: 10,
                             matching: .images) {
                    Label("添加图片", systemImage: "photo.badge.plus")
                }
                .onChange(of: selectedItems) { _, newItems in
                    Task {
                        for item in newItems {
                            if let data = try? await item.loadTransferable(type: Data.self) {
                                viewModel.addImageData(data)
                            }
                        }
                        selectedItems = []
                    }
                }
                #else
                Label("macOS 暂不支持添加图片", systemImage: "photo.badge.plus")
                    .foregroundStyle(.secondary)
                #endif
            } header: {
                Text("图片")
            }
        }
        .lolitaNavBar(title: "编辑套装", showBack: true)
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("保存") {
                    Task {
                        try? await viewModel.save()
                        dismiss()
                    }
                }
                .disabled(viewModel.name.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isSaving)
            }
        }
        #endif
        .onAppear { viewModel.load(coordinateId: coordinateId) }
    }
}
