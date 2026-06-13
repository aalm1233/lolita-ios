import SwiftUI

struct WishlistScreen: View {
    @EnvironmentObject var skinManager: SkinManager
    @StateObject private var viewModel = WishlistViewModel()

    var body: some View {
        Group {
            if viewModel.items.isEmpty {
                emptyState
            } else {
                listContent
            }
        }
        .lolitaNavBar(title: "愿望单")
        .onAppear { viewModel.load() }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("愿望单为空")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("在服饰详情中将状态设为\"愿望单\"")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var listContent: some View {
        List {
            ForEach(viewModel.prioritizedItems(), id: \.id) { item in
                NavigationLink(destination: ItemDetailScreen(itemId: item.id)) {
                    WishlistRow(item: item)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        Task { try? await viewModel.delete(item) }
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        }
        .searchable(text: $viewModel.searchText, prompt: "搜索愿望单")
    }
}

private struct WishlistRow: View {
    @EnvironmentObject var skinManager: SkinManager
    let item: Item

    var body: some View {
        HStack(spacing: 12) {
            if let firstImage = item.imageUrls.values.first, !firstImage.isEmpty {
                LolitaShimmerImage(url: ImageFileHelper.fileURL(for: firstImage))
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: skinManager.current.cornerRadiusS))
            } else {
                RoundedRectangle(cornerRadius: skinManager.current.cornerRadiusS)
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 56, height: 56)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    priorityBadge(item.priority)
                    Text("愿望单")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func priorityBadge(_ priority: ItemPriority) -> some View {
        Text(priorityLabel(priority))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(priorityColor(priority).opacity(0.12))
            .foregroundStyle(priorityColor(priority))
            .clipShape(Capsule())
    }

    private func priorityLabel(_ p: ItemPriority) -> String {
        switch p {
        case .high: return "高优先"
        case .medium: return "中优先"
        case .low: return "低优先"
        }
    }

    private func priorityColor(_ p: ItemPriority) -> Color {
        switch p {
        case .high: return .red
        case .medium: return .orange
        case .low: return .green
        }
    }
}
