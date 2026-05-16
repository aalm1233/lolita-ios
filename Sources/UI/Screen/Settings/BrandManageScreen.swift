import SwiftUI

@MainActor
final class BrandManageViewModel: ObservableObject {
    @Published var items: [Brand] = []
    private let repo = AppModule.shared.brandRepository

    func load() {
        Task {
            for await brands in repo.observeAll() {
                self.items = brands
            }
        }
    }

    func add(name: String) async throws {
        let brand = Brand(name: name, isPreset: false)
        _ = try await repo.insert(brand)
    }

    func delete(_ brand: Brand) async throws {
        try await repo.delete(brand)
    }
}

struct BrandManageScreen: View {
    @StateObject private var vm = BrandManageViewModel()
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
        .lolitaNavBar(title: "品牌管理")
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("添加") { showAdd = true }
            }
        }
        #endif
        .alert("添加品牌", isPresented: $showAdd) {
            TextField("名称", text: $newName)
            Button("确定") {
                Task { try? await vm.add(name: newName); newName = "" }
            }
            Button("取消", role: .cancel) {}
        }
        .onAppear { vm.load() }
    }
}
