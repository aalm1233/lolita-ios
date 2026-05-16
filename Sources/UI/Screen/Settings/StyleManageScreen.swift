import SwiftUI

@MainActor
final class StyleManageViewModel: ObservableObject {
    @Published var items: [Style] = []
    private let repo = AppModule.shared.styleRepository

    func load() {
        Task {
            for await styles in repo.observeAll() {
                self.items = styles
            }
        }
    }

    func add(name: String) async throws {
        let style = Style(name: name, isPreset: false)
        _ = try await repo.insert(style)
    }

    func delete(_ style: Style) async throws {
        try await repo.delete(style)
    }
}

struct StyleManageScreen: View {
    @StateObject private var vm = StyleManageViewModel()
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
        .lolitaNavBar(title: "风格管理")
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("添加") { showAdd = true }
            }
        }
        #endif
        .alert("添加风格", isPresented: $showAdd) {
            TextField("名称", text: $newName)
            Button("确定") {
                Task { try? await vm.add(name: newName); newName = "" }
            }
            Button("取消", role: .cancel) {}
        }
        .onAppear { vm.load() }
    }
}
