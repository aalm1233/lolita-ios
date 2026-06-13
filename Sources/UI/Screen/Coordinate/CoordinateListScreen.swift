import SwiftUI

struct CoordinateListScreen: View {
    @StateObject private var viewModel = CoordinateListViewModel()

    var body: some View {
        Group {
            if viewModel.coordinates.isEmpty {
                emptyState
            } else {
                listContent
            }
        }
        .lolitaNavBar(title: "套装")
        .onAppear { viewModel.load() }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("暂无套装")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("创建一个套装来搭配你的服饰吧")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var listContent: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.coordinates, id: \.id) { coordinate in
                    NavigationLink(destination: CoordinateDetailScreen(coordinateId: coordinate.id)) {
                        CoordinateRow(coordinate: coordinate)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task { try? await viewModel.delete(coordinate) }
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
            .padding()
        }
    }
}

private struct CoordinateRow: View {
    @EnvironmentObject var skinManager: SkinManager
    let coordinate: Coordinate

    var body: some View {
        LolitaCard {
            HStack(spacing: 12) {
                if let firstImage = coordinate.imageUrls.values.first,
                   !firstImage.isEmpty {
                    LolitaShimmerImage(url: ImageFileHelper.fileURL(for: firstImage))
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: skinManager.current.cornerRadiusS))
                } else {
                    RoundedRectangle(cornerRadius: skinManager.current.cornerRadiusS)
                        .fill(Color.gray.opacity(0.1))
                        .frame(width: 64, height: 64)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(coordinate.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if !coordinate.description.isEmpty {
                        Text(coordinate.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
