import SwiftUI

@MainActor
final class SeasonManageViewModel: ObservableObject {
    @Published var items: [Season] = []
    private let repo = AppModule.shared.seasonRepository

    func load() {
        Task {
            for await seasons in repo.observeAll() {
                self.items = seasons
            }
        }
    }

    func add(name: String) async throws {
        let season = Season(name: name, isPreset: false)
        _ = try await repo.insert(season)
    }

    func delete(_ season: Season) async throws {
        try await repo.delete(season)
    }
}

struct SeasonManageScreen: View {
    @StateObject private var vm = SeasonManageViewModel()
    @State private var showAdd = false
    @State private var newName = ""

    var body: some View {
        List {
            ForEach(vm.items, id: \.id) { item in
                Text(item.name)
            }
            .onDelete { idx in
                for i in idx {
                    Task { try? await vm.delete(vm.items[i]) }
                }
            }
        }
        .lolitaNavBar(title: "季节管理")
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("添加") { showAdd = true }
            }
        }
        #endif
        .alert("添加季节", isPresented: $showAdd) {
            TextField("名称", text: $newName)
            Button("确定") {
                Task { try? await vm.add(name: newName); newName = "" }
            }
            Button("取消", role: .cancel) {}
        }
        .onAppear { vm.load() }
    }
}
