import SwiftUI

struct OutfitLogListScreen: View {
    @EnvironmentObject private var skinManager: SkinManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var deleteError: String?
    @StateObject private var viewModel = OutfitLogListViewModel()

    var body: some View {
        Group {
            if viewModel.logs.isEmpty {
                VStack(spacing: 16) {
                    LolitaEmptyState(title: "还没有穿搭记录", message: "记录今天的搭配，让每次出门都有迹可循。",
                                     systemImage: "figure.stand", fillsAvailableSpace: false)
                    NavigationLink(destination: QuickOutfitLogScreen()) { Label("记录穿搭", systemImage: "plus") }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(viewModel.groupedLogs, id: \.date) { date, logs in
                        Section {
                            ForEach(logs, id: \.id) { log in
                                NavigationLink(destination: OutfitLogDetailScreen(logId: log.id)) {
                                    LolitaCollectionRow(title: log.note.isEmpty ? "穿搭记录" : log.note,
                                                        subtitle: Date(timeIntervalSince1970: TimeInterval(log.date) / 1000).formatted(date: .omitted, time: .shortened),
                                                        imagePath: log.imageUrls.values.first, symbol: "figure.stand")
                                }
                                .lolitaCollectionRowInsets()
                                .listRowBackground(colorScheme == .dark ? skinManager.current.cardColorDark : skinManager.current.cardColor)
                                .swipeActions {
                                    Button(role: .destructive) {
                                        Task {
                                            do { try await viewModel.delete(log) }
                                            catch { deleteError = userFacingError(error) }
                                        }
                                    } label: { Label("删除", systemImage: "trash") }
                                }
                            }
                        } header: { Text(date.formatted(date: .long, time: .omitted)).textCase(nil) }
                    }
                }
                .lolitaCollectionListStyle()
            }
        }
        .lolitaNavBar(title: "穿搭日记")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(destination: QuickOutfitLogScreen()) { Image(systemName: "plus") }.accessibilityLabel("记录穿搭")
            }
        }
        .alert("删除失败", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("确定") { deleteError = nil }
        } message: { Text(deleteError ?? "") }
        .onAppear { viewModel.load() }
        .onDisappear { viewModel.stopObserving() }
    }
}
