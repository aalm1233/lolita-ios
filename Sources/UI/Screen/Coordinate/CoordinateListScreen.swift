import SwiftUI

struct CoordinateListScreen: View {
    @EnvironmentObject private var skinManager: SkinManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var deleteError: String?
    @StateObject private var viewModel = CoordinateListViewModel()

    var body: some View {
        Group {
            if viewModel.coordinates.isEmpty {
                VStack(spacing: 16) {
                    LolitaEmptyState(title: "还没有套装", message: "把喜欢的服饰组合在一起，收藏你的搭配灵感。",
                                     systemImage: "photo.on.rectangle.angled", fillsAvailableSpace: false)
                    NavigationLink(destination: CoordinateEditScreen()) { Label("创建套装", systemImage: "plus") }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section {
                        ForEach(viewModel.coordinates, id: \.id) { coordinate in
                            NavigationLink(destination: CoordinateDetailScreen(coordinateId: coordinate.id)) {
                                LolitaCollectionRow(title: coordinate.name, subtitle: coordinate.description,
                                                    imagePath: coordinate.imageUrls.values.first, symbol: "photo.on.rectangle.angled")
                            }
                            .lolitaCollectionRowInsets()
                            .listRowBackground(colorScheme == .dark ? skinManager.current.cardColorDark : skinManager.current.cardColor)
                            .swipeActions {
                                Button(role: .destructive) {
                                    Task {
                                        do { try await viewModel.delete(coordinate) }
                                        catch { deleteError = userFacingError(error) }
                                    }
                                } label: { Label("删除", systemImage: "trash") }
                            }
                        }
                    } header: { LolitaCollectionHeader(title: "我的套装", count: viewModel.coordinates.count) }
                }
                .lolitaCollectionListStyle()
            }
        }
        .lolitaNavBar(title: "套装")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(destination: CoordinateEditScreen()) { Image(systemName: "plus") }.accessibilityLabel("创建套装")
            }
        }
        .alert("删除失败", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("确定") { deleteError = nil }
        } message: { Text(deleteError ?? "") }
        .onAppear { viewModel.load() }
        .onDisappear { viewModel.stopObserving() }
    }
}
