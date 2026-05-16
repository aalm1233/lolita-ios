import SwiftUI

struct StatsPageScreen: View {
    @StateObject private var viewModel = StatsPageViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    StatCard(title: "总服饰", value: "\(viewModel.totalItems)", color: .blue)
                    StatCard(title: "已拥有", value: "\(viewModel.ownedCount)", color: .green)
                    StatCard(title: "愿望单", value: "\(viewModel.wishedCount)", color: .pink)
                    StatCard(title: "穿搭记录", value: "\(viewModel.totalOutfits)", color: .orange)
                }

                if !viewModel.styleDistribution.isEmpty {
                    LolitaSection(title: "风格分布") {
                        ForEach(viewModel.styleDistribution.prefix(10), id: \.0) { style, count in
                            HStack {
                                Text(style)
                                Spacer()
                                Text("\(count)").foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .padding()
        }
        .lolitaNavBar(title: "统计")
        .onAppear { viewModel.load() }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        LolitaCard(variant: .compact) {
            VStack(spacing: 4) {
                Text(value).font(.largeTitle.weight(.bold)).foregroundStyle(color)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
