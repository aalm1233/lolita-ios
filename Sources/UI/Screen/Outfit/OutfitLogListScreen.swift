import SwiftUI

struct OutfitLogListScreen: View {
    @State private var deleteError: String?
    @State private var deleteRequest: LolitaDeleteRequest?
    @State private var search = ""
    @State private var isSearching = false
    @FocusState private var searchFocused: Bool
    @StateObject private var viewModel = OutfitLogListViewModel()
    @StateObject private var collection = ItemListViewModel()

    private var groupedLogs: [(date: Date, logs: [OutfitLog])] {
        viewModel.groupedLogs.compactMap { group in
            let logs = group.logs.filter {
                search.isEmpty || $0.note.localizedCaseInsensitiveContains(search)
                    || group.date.formatted(date: .long, time: .omitted).localizedCaseInsensitiveContains(search)
                    || collection.itemsByOutfit($0.id).contains { $0.name.localizedCaseInsensitiveContains(search) }
            }
            return logs.isEmpty ? nil : (group.date, logs)
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            if isSearching {
                LolitaHomeToolbar(isSearching: true, onSearch: {}, onCancel: {
                    searchFocused = false
                    search = ""
                    isSearching = false
                }, clearSearch: search.isEmpty ? nil : { search = ""; searchFocused = true }) {
                    EmptyView()
                } actions: {
                    EmptyView()
                } searchField: {
                    TextField("搜索日记、日期或服饰", text: $search)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .focused($searchFocused)
                        .task { searchFocused = true }
                        .onSubmit { searchFocused = false }
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .submitLabel(.search)
                        #endif
                }
                .padding(.horizontal, 12).padding(.vertical, 2)
            } else {
                LolitaRootToolbar(title: "穿搭日记", subtitle: groupedLogs.isEmpty ? nil : "\(groupedLogs.reduce(0) { $0 + $1.logs.count }) 篇 · \(groupedLogs.count) 天") {
                    Button { isSearching = true } label: {
                        Image(systemName: "magnifyingglass").frame(width: 44, height: 44)
                    }.accessibilityLabel("搜索穿搭日记")
                    NavigationLink(destination: QuickOutfitLogScreen()) {
                        Image(systemName: "sun.max").frame(width: 44, height: 44)
                    }.accessibilityLabel("记录今日穿搭")
                    NavigationLink(destination: OutfitLogEditScreen(logId: 0)) {
                        Image(systemName: "plus").frame(width: 44, height: 44)
                    }.accessibilityLabel("新增穿搭记录")
                }
            }
            if groupedLogs.isEmpty {
                VStack(spacing: 16) {
                    LolitaEmptyState(title: search.isEmpty ? "还没有穿搭记录" : "没有找到匹配结果",
                                     message: search.isEmpty ? "记录今天的搭配，让每次出门都有迹可循。" : "可搜索日记、日期或服饰名称。",
                                     systemImage: search.isEmpty ? "figure.stand" : "magnifyingglass", fillsAvailableSpace: false)
                    if search.isEmpty {
                        NavigationLink(destination: OutfitLogEditScreen(logId: 0)) { Label("记录穿搭", systemImage: "plus") }.buttonStyle(.borderedProminent)
                    } else { Button("清除搜索") { search = "" }.buttonStyle(.bordered) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(groupedLogs, id: \.date) { group in
                        Section {
                            ForEach(group.logs, id: \.id) { log in
                                NavigationLink(destination: OutfitLogDetailScreen(logId: log.id)) {
                                    OutfitLogCollectionCard(log: log, items: collection.itemsByOutfit(log.id))
                                }.buttonStyle(.plain)
                                .lolitaCardRow()
                                .contextMenu {
                                    NavigationLink(destination: OutfitLogEditScreen(logId: log.id)) { Label("编辑", systemImage: "pencil") }
                                    Button("删除", role: .destructive) { delete(log) }
                                }
                                .swipeActions { Button("删除", role: .destructive) { delete(log) } }
                            }
                        } header: { Text(group.date.formatted(.dateTime.year().month().day())).textCase(nil) }
                    }
                }.lolitaCardListStyle()
            }
        }
        .lolitaNavBar(title: "穿搭日记", isHidden: true)
        .scrollDismissesKeyboard(.interactively)
        .alert("删除失败", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("确定") { deleteError = nil }
        } message: { Text(deleteError ?? "") }
        .lolitaDeleteConfirmation($deleteRequest)
        .onAppear { viewModel.load(); collection.load() }
        .onDisappear { searchFocused = false; viewModel.stopObserving(); collection.stopObserving() }
    }
    private func delete(_ log: OutfitLog) {
        deleteRequest = LolitaDeleteRequest(name: log.note.isEmpty ? "这篇穿搭日记" : log.note) {
            Task { do { try await viewModel.delete(log) } catch { deleteError = userFacingError(error) } }
        }
    }
}
