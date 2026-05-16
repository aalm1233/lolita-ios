import SwiftUI
#if os(iOS)
import PhotosUI
#endif

struct ItemEditScreen: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var skin: DefaultSkin
    @StateObject private var viewModel = ItemEditViewModel()

    let itemId: Int64

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
                Picker("状态", selection: $viewModel.status) {
                    Text("已拥有").tag(ItemStatus.owned)
                    Text("想要").tag(ItemStatus.wished)
                    Text("待尾款").tag(ItemStatus.pendingBalance)
                }
                Picker("优先级", selection: $viewModel.priority) {
                    Text("高").tag(ItemPriority.high)
                    Text("中").tag(ItemPriority.medium)
                    Text("低").tag(ItemPriority.low)
                }
            } header: {
                Text("属性")
            }

            Section {
                Picker("品牌", selection: $viewModel.brandId) {
                    ForEach(viewModel.brands, id: \.id) { brand in
                        Text(brand.name).tag(brand.id)
                    }
                }
                Picker("分类", selection: $viewModel.categoryId) {
                    ForEach(viewModel.categories, id: \.id) { category in
                        Text(category.name).tag(category.id)
                    }
                }
                TextField("风格", text: $viewModel.style)
                TextField("季节", text: $viewModel.season)
                TextField("尺码", text: $viewModel.size)
                Picker("位置", selection: $viewModel.locationId) {
                    Text("无").tag(nil as Int64?)
                    ForEach(viewModel.locations, id: \.id) { location in
                        Text(location.name).tag(location.id as Int64?)
                    }
                }
            } header: {
                Text("分类")
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
        .lolitaNavBar(title: "编辑服饰", showBack: true, onBack: { dismiss() })
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
        .task { await viewModel.load(itemId: itemId) }
    }
}
