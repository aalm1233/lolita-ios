import SwiftUI

struct OutfitLogDetailScreen: View {
    @EnvironmentObject var skinManager: SkinManager
    @StateObject private var viewModel = OutfitLogDetailViewModel()

    let logId: Int64

    var body: some View {
        ScrollView {
            VStack(spacing: skinManager.current.cardGap) {
                ImageGalleryPager(urls: viewModel.imageUrls)

                if let log = viewModel.log {
                    LolitaCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(formattedDate(log.date))
                                .font(.title2.weight(.bold))

                            if !log.note.isEmpty {
                                Text(log.note)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if !viewModel.items.isEmpty {
                    LolitaSection(title: "关联服饰") {
                        ForEach(viewModel.items, id: \.id) { item in
                            ItemRow(item: item)
                        }
                    }
                }
            }
            .padding()
        }
        .lolitaNavBar(title: viewModel.log.map { formattedDate($0.date) } ?? "穿搭记录", showBack: true)
#if os(iOS)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(destination: OutfitLogEditScreen(logId: logId)) {
                    Text("编辑")
                }
            }
        }
#endif
        .onAppear { viewModel.load(logId: logId) }
    }

    private func formattedDate(_ timestamp: Int64) -> String {
        Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
            .formatted(date: .long, time: .omitted)
    }
}
