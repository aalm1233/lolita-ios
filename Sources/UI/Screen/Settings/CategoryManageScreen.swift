import SwiftUI

@MainActor
final class CategoryManageViewModel: ObservableObject {
    @Published var items: [Category] = []
    private let repo = AppModule.shared.categoryRepository

    func load() {
        Task {
            for await categories in repo.observeAll() {
                self.items = categories
            }
        }
    }

    func add(name: String, group: CategoryGroup) async throws {
        let category = Category(name: name, group: group, isPreset: false)
        _ = try await repo.insert(category)
    }

    func delete(_ category: Category) async throws {
        try await repo.delete(category)
    }
}

struct CategoryManageScreen: View {
    @StateObject private var vm = CategoryManageViewModel()
    @State private var showAdd = false
    @State private var newName = ""
    @State private var newGroup: CategoryGroup = .clothing

    private func groupLabel(_ group: CategoryGroup) -> String {
        switch group {
        case .clothing: return "服饰"
        case .accessory: return "配件"
        }
    }

    var body: some View {
        List {
            ForEach(vm.items, id: \.id) { item in
                HStack {
                    Text(item.name)
                    Spacer()
                    Text(groupLabel(item.group))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onDelete { idx in
                for i in idx {
                    Task { try? await vm.delete(vm.items[i]) }
                }
            }
        }
        .lolitaNavBar(title: "分类管理")
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("添加") { showAdd = true }
            }
        }
        #endif
        .alert("添加分类", isPresented: $showAdd) {
            TextField("名称", text: $newName)
            Picker("类型", selection: $newGroup) {
                Text("服饰").tag(CategoryGroup.clothing)
                Text("配件").tag(CategoryGroup.accessory)
            }
            Button("确定") {
                Task { try? await vm.add(name: newName, group: newGroup); newName = "" }
            }
            Button("取消", role: .cancel) {}
        }
        .onAppear { vm.load() }
    }
}
