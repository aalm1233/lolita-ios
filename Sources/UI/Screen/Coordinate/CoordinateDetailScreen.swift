import SwiftUI

struct CoordinateDetailScreen: View {
    @EnvironmentObject var skinManager: SkinManager
    @StateObject private var viewModel = CoordinateDetailViewModel()

    let coordinateId: Int64

    var body: some View {
        ScrollView {
            VStack(spacing: skinManager.current.cardGap) {
                ImageGalleryPager(urls: viewModel.imageUrls)

                LolitaCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(viewModel.coordinate?.name ?? "")
                            .font(.title2.weight(.bold))

                        if let desc = viewModel.coordinate?.description, !desc.isEmpty {
                            Text(desc)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                LolitaSection(title: "套装价格") { Text(String(format: "¥%.2f", viewModel.totalPrice)) }

                if !viewModel.items.isEmpty {
                    LolitaSection(title: "包含服饰") {
                        ForEach(viewModel.items, id: \.id) { item in
                            NavigationLink(destination: ItemDetailScreen(itemId: item.id)) { ItemRow(item: item) }
                        }
                    }
                }
            }
            .padding()
        }
        .lolitaNavBar(title: "套装详情", showBack: true)
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(destination: CoordinateEditScreen(coordinateId: coordinateId)) {
                    Text("编辑")
                }
            }
        }
        #endif
        .onAppear { viewModel.load(coordinateId: coordinateId) }
    }
}

