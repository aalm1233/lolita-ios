import SwiftUI

struct OutfitLogListScreen: View {
    @EnvironmentObject var skinManager: SkinManager
    @StateObject private var viewModel = OutfitLogListViewModel()

    var body: some View {
        Group {
            if viewModel.logs.isEmpty {
                emptyState
            } else {
                listContent
            }
        }
        .lolitaNavBar(title: "穿搭记录")
#if os(iOS)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(destination: QuickOutfitLogScreen()) {
                    Image(systemName: "plus")
                }
            }
        }
#endif
        .onAppear { viewModel.load() }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.2")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("暂无穿搭记录")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("记录你的每日穿搭吧")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var listContent: some View {
        ScrollView {
            LazyVStack(spacing: skinManager.current.cardGap) {
                ForEach(viewModel.groupedLogs, id: \.date) { date, logs in
                    sectionHeader(date)
                    ForEach(logs, id: \.id) { log in
                        NavigationLink(destination: OutfitLogDetailScreen(logId: log.id)) {
                            OutfitLogRow(log: log)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task { try? await viewModel.delete(log) }
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func sectionHeader(_ date: Date) -> some View {
        HStack {
            Text(date.formatted(date: .long, time: .omitted))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 4)
    }
}

private struct OutfitLogRow: View {
    @EnvironmentObject var skinManager: SkinManager
    let log: OutfitLog

    var body: some View {
        LolitaCard {
            HStack(spacing: 12) {
                if let firstImage = log.imageUrls.values.first,
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
                    Text(log.note.isEmpty ? "穿搭记录" : log.note)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(2)

                    Text(Date(timeIntervalSince1970: TimeInterval(log.date) / 1000),
                         style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
