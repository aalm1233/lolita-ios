import SwiftUI

struct CoordinateDetailScreen: View {
    @EnvironmentObject var skin: DefaultSkin
    @StateObject private var viewModel = CoordinateDetailViewModel()

    let coordinateId: Int64

    var body: some View {
        ScrollView {
            VStack(spacing: skin.cardGap) {
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

                if !viewModel.items.isEmpty {
                    LolitaSection(title: "包含服饰") {
                        ForEach(viewModel.items, id: \.id) { item in
                            ItemRow(item: item)
                        }
                    }
                }
            }
            .padding()
        }
        .lolitaNavBar(title: viewModel.coordinate?.name ?? "套装", showBack: true)
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

